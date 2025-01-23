package main

import "core:fmt"
import "core:math/rand"
import "core:net"
import "core:sync"
import "core:time"
import "core:thread"

import "src:basic/mem"
import "src:term"

MAX_CLIENT_CONNECTIONS :: 10
RECV_TIMEOUT_DURATION  :: time.Millisecond * 100

@(private="file")
perm_arena: mem.Arena

server_socket: net.TCP_Socket
connection_thread: ^thread.Thread

client_store: Client_Store
message_store: Message_Store

server_entry :: proc()
{
  mem.init_arena_static(&perm_arena)
  init_message_store(&message_store)

  endpoint, _ := net.parse_endpoint(ENDPOINT)

  // --- Start server ---------------
  listen_err: net.Network_Error
  server_socket, listen_err = net.listen_tcp(endpoint, MAX_CLIENT_CONNECTIONS)
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
    temp := mem.begin_temp(mem.get_scratch())
    defer mem.end_temp(temp)

    for client in client_store.data
    {
      if !client_is_valid(client) do continue
      
      // --- Listen for messages ---------------
      packet_bytes: [MAX_MESSAGE_SIZE]byte
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
                    MAX_CLIENT_CONNECTIONS)
        term.color(.WHITE)

        packet := create_packet(.CLIENT_DISCONNECTED, nil, {client.user})
        packet_bytes := serialize_packet(&packet, temp.arena)

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
      packet := deserialize_packet(packet_bytes[:bytes_read], &perm_arena)
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
          ret_packet := create_packet(.MESSAGE_FROM_SERVER,
                                          {message_store.data[message_store.count-1]}, 
                                          {get_client_by_id(sender.user.id).user})
          ret_sender_id := ret_packet.messages[0].sender_id
          
          if !client_is_valid(other_client)        do continue
          if other_client.user.id == ret_sender_id do continue

          ret_packet_bytes := serialize_packet(&ret_packet, temp.arena)
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

connection_thread_proc :: #force_inline proc(this: ^thread.Thread)
{
  mem.init_scratches()
  
  for
  {
    time.sleep(time.Millisecond * 100)

    if client_store.count == MAX_CLIENT_CONNECTIONS do continue

    temp := mem.begin_temp(mem.get_scratch())
    defer mem.end_temp(temp)

    if client_store.count < MAX_CLIENT_CONNECTIONS
    {
      client_socket, _, _ := net.accept_tcp(server_socket)

      recv_packet_bytes: [MAX_USER_SIZE]byte
      bytes_read, recv_err := net.recv_tcp(client_socket, recv_packet_bytes[:])
      if recv_err != nil || bytes_read == 0 do break

      net.set_option(client_socket, .Receive_Timeout, RECV_TIMEOUT_DURATION)

      packet := deserialize_packet(recv_packet_bytes[:], &perm_arena)
      packet.users[0].color = rand.choice_enum(Color_Kind)
      push_client(Client{client_socket, packet.users[0]})

      term.color(.GRAY)
      fmt.printf("%s has entered the chat. (%i/%i)\n", 
                  packet.users[0].name,
                  client_store.count, 
                  MAX_CLIENT_CONNECTIONS)
      term.color(.WHITE)
      
      user := packet.users[0]
      packet = create_packet(.CLIENT_CONNECTED, nil, {user})
      send_packet_bytes := serialize_packet(&packet, temp.arena)

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

Client :: struct
{
  socket: net.TCP_Socket,
  user: User,
}

Client_Store :: struct
{
  data: [MAX_CLIENT_CONNECTIONS]Client,
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

  for other_client, i in client_store.data do if !client_is_valid(other_client) 
  {
    client_store.data[i].socket = client.socket
    client_store.data[i].user = client.user
    client_store.count += 1
    
    fmt.println("Pushed client of ID", client.user.id)
    break
  }

  sync.mutex_unlock(&client_store.lock)
}

pop_client :: proc(client: ^Client)
{
  if client == nil do return

  sync.mutex_lock(&client_store.lock)
  client^ = {}
  client_store.count -= 1
  sync.mutex_unlock(&client_store.lock)
  
  fmt.println("Popped client of ID", client.user.id)
}

get_client_by_id :: proc(id: User_ID) -> ^Client
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
