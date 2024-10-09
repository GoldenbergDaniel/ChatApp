package client

import "core:fmt"
import "core:net"
import "core:os"
import "core:math/rand"

import "src:common"

client_socket: net.TCP_Socket
user: common.User
endpoint_str: string = "127.0.0.1:3030"

main :: proc()
{
  fmt.print("Display name: ")
  name_buf: [128]byte
  name_len, read_name_err := os.read(os.stdin, name_buf[:])
  if read_name_err != nil
  {
    fmt.eprintln(read_name_err)
    return
  }

  user.name = cast(string) name_buf[:name_len-1]
  user.id = rand.uint32()

  fmt.println("Client started.")

  for true
  {
    defer free_all(context.temp_allocator)

    dial_err: net.Network_Error
    client_socket, dial_err = net.dial_tcp(endpoint_str)
    if dial_err != nil
    {
      net.close(client_socket)
      continue
    }
    else
    {
      user_bytes := common.bytes_from_user(user, context.temp_allocator)
      _, send_err := net.send_tcp(client_socket, user_bytes)
      if send_err != nil
      {
        fmt.eprintln(send_err)
        continue
      }

      fmt.println("Connected to server on", endpoint_str)
      break
    }
  }

  for true
  {
    fmt.print("> ")
    message_buf: [common.MAX_MESSAGE_SIZE]byte
    message_len, read_msg_err := os.read(os.stdin, message_buf[:])
    if read_msg_err != nil
    {
      fmt.eprintln(read_msg_err)
      break
    }

    message: common.Message
    message.sender = user.id
    message.data = cast(string) message_buf[:message_len-1]
    message_bytes := common.bytes_from_message(message, context.temp_allocator)
    _, send_err := net.send_tcp(client_socket, message_bytes)
    if send_err != nil
    {
      fmt.eprintln(send_err)
      continue
    }
  }
}
