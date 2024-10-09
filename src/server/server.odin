package server

import "core:fmt"
import "core:net"
import "core:time"
import "core:math/rand"

import "src:common"
import "src:term"

MAX_CONNECTIONS  :: 2
RECV_TIMEOUT_DUR :: time.Millisecond * 100

Client :: struct
{
  socket: net.TCP_Socket,
  user: common.User,
}

clients: [MAX_CONNECTIONS]Client
client_count: int

main :: proc()
{
  endpoint: net.Endpoint
  endpoint.address, _ = net.parse_ip4_address("127.0.0.1")
  endpoint.port = 3030

  socket, listen_err := net.listen_tcp(endpoint, MAX_CONNECTIONS)
  if listen_err != nil
  {
    fmt.eprintln("Error creating, binding, or listening.", listen_err)
    return
  }

  fmt.println("Server started on", net.endpoint_to_string(endpoint))
  fmt.printf("Waiting for clients 0/%i\n", MAX_CONNECTIONS)
  
  for true
  {
    client_soc, _, _ := net.accept_tcp(socket)
    if client_count < MAX_CONNECTIONS
    {
      user_bytes: [128]byte
      bytes_read, recv_err := net.recv_tcp(client_soc, user_bytes[:])
      if recv_err != nil || bytes_read == 0 do break

      clients[client_count].socket = client_soc
      net.set_option(clients[client_count].socket, .Receive_Timeout, RECV_TIMEOUT_DUR)

      user := common.user_from_bytes(user_bytes[:bytes_read], context.allocator)
      user.color = rand.choice_enum(common.ColorKind)
      clients[client_count].user = user

      client_count += 1

      fmt.println(user_bytes)

      term.color(common.color_to_term_color(user.color))
      fmt.print(user.name)
      term.color(.WHITE)
      fmt.printf(" has entered the chat. %i/%i\n", 
                  user.name, 
                  client_count, 
                  MAX_CONNECTIONS)
    }

    if client_count == MAX_CONNECTIONS do break
  }
  
  for is_running := true; is_running;
  {
    for client in clients[:client_count]
    {
      message_bytes: [128]byte
      bytes_read, recv_err := net.recv_tcp(client.socket, message_bytes[:])
      if recv_err != nil
      {
        err, ok := recv_err.(net.TCP_Recv_Error)
        if !ok || (ok && err != .Timeout)
        {
          fmt.eprintln(recv_err)
        }

        continue
      }
      
      if bytes_read == 0
      {
        // fmt.println("User disconnected.")
        continue
      }
      
      message := common.message_from_bytes(message_bytes[:bytes_read], context.allocator)
      if message.data == "q!"
      {
        fmt.println("Recieved quit signal.")
        is_running = false
        break
      }

      sender := user_from_user_id(message.sender)
      term.color(common.color_to_term_color(sender.color))
      fmt.print(sender.name)
      term.color(.WHITE)
      fmt.printf(": %s\n", message.data)
    }
  }

  fmt.println("Server closed.")
}

user_from_user_id :: proc(id: common.UserID) -> common.User
{
  result: common.User

  for client in clients
  {
    if client.user.id == id
    {
      result = client.user 
      break
    }
  }

  return result
}
