package server

import "core:fmt"
import "core:net"
import "core:sync"
import "core:time"
import "core:thread"
import "core:math/rand"

import "src:common"
import "src:term"

MAX_CLIENT_CONNECTIONS :: 10
RECV_TIMEOUT_DURATION  :: time.Millisecond * 100

server_socket: net.TCP_Socket
client_store: ClientStore
connection_thread: ^thread.Thread

main :: proc()
{
  endpoint: net.Endpoint
  endpoint.address, _ = net.parse_ip4_address("127.0.0.1")
  endpoint.port = 3030

  // --- Start server ---------------
  listen_err: net.Network_Error
  server_socket, listen_err = net.listen_tcp(endpoint, MAX_CLIENT_CONNECTIONS)
  if listen_err != nil
  {
    fmt.eprintln("Error creating, binding, or listening.", listen_err)
    return
  }

  fmt.println("Server started on", net.endpoint_to_string(endpoint))

  connection_thread = thread.create(connection_thread_proc)
  thread.start(connection_thread)
  
  for is_running := true; is_running;
  {
    for client in client_store.data[:client_store.count]
    {
      if !client_is_valid(client) do continue
      
      // --- Listen for message ---------------
      message_bytes: [common.MAX_MESSAGE_SIZE]byte
      bytes_read, recv_err := net.recv_tcp(client.socket, message_bytes[:])
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

        pop_client(get_client_by_id(client.user.id))
        continue
      }

      // --- Handle message ---------------
      message := common.message_from_bytes(message_bytes[:bytes_read], context.allocator)
      if message.data == "q!"
      {
        fmt.print("Recieved quit signal.\n")
        is_running = false
      }
      else
      {
        sender := get_client_by_id(message.sender).user
        term.color(common.color_to_term_color(sender.color))
        fmt.print(sender.name)
        term.color(.WHITE)
        fmt.printf(": %s\n", message.data)
      }
    }
  }

  thread.join(connection_thread)
  net.close(server_socket)
}

connection_thread_proc :: proc(this: ^thread.Thread)
{
  for
  {
    time.sleep(time.Millisecond * 100)

    if client_store.count == MAX_CLIENT_CONNECTIONS do continue

    client_socket, _, _ := net.accept_tcp(server_socket)
    if client_store.count < MAX_CLIENT_CONNECTIONS
    {
      user_bytes: [common.MAX_USER_SIZE]byte
      bytes_read, recv_err := net.recv_tcp(client_socket, user_bytes[:])
      if recv_err != nil || bytes_read == 0 do break

      net.set_option(client_socket, .Receive_Timeout, RECV_TIMEOUT_DURATION)

      user := common.user_from_bytes(user_bytes[:bytes_read], context.allocator)
      user.color = rand.choice_enum(common.ColorKind)

      push_client(Client{client_socket, user})

      term.color(.GRAY)
      fmt.printf("%s has entered the chat. (%i/%i)\n", 
                  user.name,
                  client_store.count, 
                  MAX_CLIENT_CONNECTIONS)
      term.color(.WHITE)
    }
  }
}


// @Clients //////////////////////////////////////////////////////////////////////////////


Client :: struct
{
  socket: net.TCP_Socket,
  user: common.User,
}

ClientStore :: struct
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
  assert(client_store.count < MAX_CLIENT_CONNECTIONS)

  sync.mutex_lock(&client_store.lock)
  client_store.data[client_store.count].socket = client.socket
  client_store.data[client_store.count].user = client.user
  client_store.count += 1
  sync.mutex_unlock(&client_store.lock)
}

pop_client :: proc(client: ^Client)
{
  assert(client_store.count > 0)

  sync.mutex_lock(&client_store.lock)
  for &other_client in client_store.data
  {
    if &other_client == client
    {
      other_client = {}
      client_store.count -= 1
    }
  }

  sync.mutex_unlock(&client_store.lock)
}

get_client_by_id :: proc(id: common.UserID) -> ^Client
{
  result: ^Client

  for &client in client_store.data
  {
    if client.user.id == id
    {
      result = &client
      break
    }
  }

  return result
}
