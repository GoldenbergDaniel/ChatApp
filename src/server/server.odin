package server

import "core:fmt"
import "core:math/rand"
import "core:net"
import "core:sync"
import "core:time"
import "core:thread"

import com "src:common"
import "src:basic/mem"
import "src:term"

RECV_TIMEOUT_DURATION  :: time.Millisecond * 100

perm_arena: mem.Arena
temp_arena: mem.Arena

server_socket: net.TCP_Socket
connection_thread: ^thread.Thread

client_store: Client_Store
message_store: Message_Store

main :: proc()
{
  mem.init_arena_static(&perm_arena)
  mem.init_arena_growing(&temp_arena)

  init_message_store(&message_store)

  endpoint, _ := net.parse_endpoint("127.0.0.1:3030")

  // --- Start server ---------------
  listen_err: net.Network_Error
  server_socket, listen_err = net.listen_tcp(endpoint, com.MAX_CLIENT_CONNECTIONS)
  if listen_err != nil
  {
    fmt.eprintln("Error creating, binding, or listening.", listen_err)
    return
  }

  connection_thread = thread.create(connection_thread_proc)
  thread.start(connection_thread)

  fmt.println("Server started on", net.endpoint_to_string(endpoint))
  
  for is_running := true; is_running;
  {
    for client in client_store.data
    {
      if !client_is_valid(client) do continue
      
      // --- Listen for messages ---------------
      packet_bytes: [com.MAX_MESSAGE_SIZE]byte
      bytes_read, recv_err := net.recv_tcp(client.socket, packet_bytes[:])
      if recv_err != nil
      {
        err, ok := recv_err.(net.TCP_Recv_Error)
        if ok && err == .Timeout
        {
          continue
        }
        else
        {
          fmt.eprintln(recv_err)
          break
        }
      }
      
      // --- Client disconnected ---------------
      if bytes_read == 0
      {
        term.color(.GRAY)
        fmt.printf("%s has left the chat. (%i/%i)\n", 
                    client.user.name,
                    client_store.count-1, 
                    com.MAX_CLIENT_CONNECTIONS)
        term.color(.WHITE)

        packet := com.create_packet(.CLIENT_DISCONNECTED, nil, {client.user})
        packet_bytes := com.serialize_packet(&packet, &temp_arena)

        for other_client in client_store.data
        {
          if !client_is_valid(other_client) do continue
          if other_client.user.id == client.user.id do continue

          _, send_err := net.send_tcp(other_client.socket, packet_bytes)
          if send_err != nil
          {
            fmt.eprintln(send_err)
            continue
          }
        }

        pop_client(get_client_by_id(client.user.id))
        continue
      }

      // --- Handle message ---------------
      packet := com.deserialize_packet(packet_bytes[:bytes_read], &perm_arena)
      message := packet.messages[0]
      push_message(message)

      if message.data == "q!"
      {
        fmt.print("Recieved quit signal.\n")
        is_running = false
      }
      else
      {
        sender := get_client_by_id(message.sender_id)
        if sender == nil do continue

        term.color(.GRAY)
        fmt.printf("%s sent a message: %s\n", sender.user.name, message.data)
        term.color(.WHITE)
        
        // --- Send message ---------------
        for other_client in client_store.data
        {
          ret_packet := com.create_packet(.MESSAGE_FROM_SERVER,
                                          {message_store.data[message_store.count-1]}, 
                                          {get_client_by_id(sender.user.id).user})
          ret_sender_id := ret_packet.messages[0].sender_id
          
          if !client_is_valid(other_client)        do continue
          if other_client.user.id == ret_sender_id do continue

          ret_packet_bytes := com.serialize_packet(&ret_packet, &temp_arena)
          _, send_err := net.send_tcp(other_client.socket, ret_packet_bytes)
          if send_err != nil
          {
            fmt.eprintln(send_err)
          }
        }
      }
    }
  }

  thread.terminate(connection_thread, 0)
}

connection_thread_proc :: proc(this: ^thread.Thread)
{
  for
  {
    time.sleep(time.Millisecond * 100)

    if client_store.count == com.MAX_CLIENT_CONNECTIONS do continue

    defer mem.clear_arena(&temp_arena)

    if client_store.count < com.MAX_CLIENT_CONNECTIONS
    {
      client_socket, _, _ := net.accept_tcp(server_socket)

      recv_packet_bytes: [com.MAX_USER_SIZE]byte
      bytes_read, recv_err := net.recv_tcp(client_socket, recv_packet_bytes[:])
      if recv_err != nil || bytes_read == 0 do break

      net.set_option(client_socket, .Receive_Timeout, RECV_TIMEOUT_DURATION)

      packet := com.deserialize_packet(recv_packet_bytes[:], &perm_arena)
      packet.users[0].color = rand.choice_enum(com.Color_Kind)
      push_client(Client{client_socket, packet.users[0]})

      term.color(.GRAY)
      fmt.printf("%s has entered the chat. (%i/%i)\n", 
                  packet.users[0].name,
                  client_store.count, 
                  com.MAX_CLIENT_CONNECTIONS)
      term.color(.WHITE)
      
      user := packet.users[0]
      packet = com.create_packet(.CLIENT_CONNECTED, nil, {user})
      send_packet_bytes := com.serialize_packet(&packet, &temp_arena)

      for other_client in client_store.data
      {
        if !client_is_valid(other_client)  do continue
        if other_client.user.id == user.id do continue

        _, send_err := net.send_tcp(other_client.socket, send_packet_bytes)
        if send_err != nil
        {
          fmt.eprintln(send_err)
          continue
        }
      }
    }
  }
}


// @Clients //////////////////////////////////////////////////////////////////////////////


Client :: struct
{
  socket: net.TCP_Socket,
  user: com.User,
}

Client_Store :: struct
{
  data: [com.MAX_CLIENT_CONNECTIONS]Client,
  count: int,
  lock: sync.Mutex
}

client_is_valid :: proc(client: Client) -> bool
{
  return client.user.id != 0
}

push_client :: proc(client: Client)
{
  sync.mutex_lock(&client_store.lock)

  for other_client, i in client_store.data
  {
    if !client_is_valid(other_client) 
    {
      client_store.data[i].socket = client.socket
      client_store.data[i].user = client.user
      client_store.count += 1
      fmt.println("Pushed", client.user)
      break
    }
  }

  sync.mutex_unlock(&client_store.lock)
}

pop_client :: proc(client: ^Client)
{
  if client == nil do return

  sync.mutex_lock(&client_store.lock)
  fmt.println("Popped", client.user)
  client^ = {}
  client_store.count -= 1
  sync.mutex_unlock(&client_store.lock)
}

get_client_by_id :: proc(id: com.User_ID) -> ^Client
{
  result: ^Client
  for &client in client_store.data
  {
    if client == {} do continue

    if client.user.id == id
    {
      result = &client
      break
    }
  }

  return result
}

// Messages //////////////////////////////////////////////////////////////////////////////

Message_Store :: struct
{
  data: [dynamic]com.Message,
  free_list: [dynamic]bool,
  count: int,
  arena: mem.Arena,
}

init_message_store :: proc(store: ^Message_Store)
{
  mem.init_arena_growing(&store.arena)
  store.data = make([dynamic]com.Message, 16, mem.allocator(&store.arena))
  store.free_list = make([dynamic]bool, 16, mem.allocator(&store.arena))
}

push_message :: proc(message: com.Message)
{
  for idx in 0..<message_store.count
  {
    if message_store.free_list[idx] == true
    {
      message_store.data[idx] = message
      return 
    }
  }

  assign_at(&message_store.data, message_store.count, message)
  assign_at(&message_store.free_list, message_store.count, false)
  message_store.count += 1
}

pop_message :: proc(idx: int)
{
  message_store.data[idx] = {}
  message_store.free_list[idx] = true
}

get_message :: proc(idx := -1) -> com.Message
{
  i := idx < 0 ? message_store.count-1 : idx
  return message_store.data[i]
}
