package server

import "core:fmt"
import "core:net"
import "core:time"
import "core:thread"
import "core:math/rand"

import "src:common"
import "src:term"

MAX_CLIENT_CONNECTIONS :: 10
RECV_TIMEOUT_DURATION  :: time.Millisecond * 100

server_socket: net.TCP_Socket
clients: ClientStore
connection_thread: ^thread.Thread

main :: proc()
{
  endpoint: net.Endpoint
  endpoint.address, _ = net.parse_ip4_address("127.0.0.1")
  endpoint.port = 3030

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
    for client in clients.data[:clients.count]
    {
      if !client_is_valid(client) do continue
      
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
      
      // Client disconnected
      if bytes_read == 0
      {
        term.color(.GRAY)
        fmt.printf("%s has entered the chat. (%i/%i)\n", 
                    client.user.name,
                    clients.count-1, 
                    MAX_CLIENT_CONNECTIONS)
        term.color(.WHITE)

        pop_client(get_client(client.user.id))
        continue
      }
      
      message := common.message_from_bytes(message_bytes[:bytes_read], context.allocator)
      if message.data == "q!"
      {
        fmt.print("Recieved quit signal.\n")
        is_running = false
      }
      else
      {
        sender := get_client(message.sender).user
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
  for true
  {
    if clients.count == MAX_CLIENT_CONNECTIONS do continue

    client_socket, _, _ := net.accept_tcp(server_socket)
    if clients.count < MAX_CLIENT_CONNECTIONS
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
                  clients.count, 
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
}

client_is_valid :: proc(client: Client) -> bool
{
  return client.user.id != 0
}

push_client :: proc(client: Client)
{
  assert(clients.count < MAX_CLIENT_CONNECTIONS)

  clients.data[clients.count].socket = client.socket
  clients.data[clients.count].user = client.user
  clients.count += 1
}

pop_client :: proc(client: ^Client)
{
  assert(clients.count > 0)

  for &other_client in clients.data
  {
    if &other_client == client
    {
      other_client = {}
      clients.count -= 1
    }
  }
}

get_client :: proc
{
  get_client_by_id,
  get_client_at_idx,
}

get_client_by_id :: proc(id: common.UserID) -> ^Client
{
  result: ^Client

  for &client in clients.data
  {
    if client.user.id == id
    {
      result = &client
      break
    }
  }

  return result
}

get_client_at_idx :: proc(idx: int) -> ^Client
{
  result: ^Client

  if client_is_valid(clients.data[idx])
  {
    result = &clients.data[idx]
  }

  return result
}
