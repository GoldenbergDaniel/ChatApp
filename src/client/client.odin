package client

import "core:fmt"
import "core:net"
import "core:thread"
import "core:os"

import com "src:common"
import "src:basic/mem"
import "src:term"

perm_arena: mem.Arena
temp_arena: mem.Arena

socket: net.TCP_Socket
user: com.User
endpoint_str: string = "127.0.0.1:3030"
receive_messages_thread: ^thread.Thread

shutdown: bool

main :: proc()
{
  mem.init_arena_static(&perm_arena)
  context.allocator = mem.allocator(&perm_arena)

  mem.init_arena_growing(&temp_arena)
  context.temp_allocator = mem.allocator(&temp_arena)

  // --- Prompt user's name ---------------
  fmt.print("Display name: ")
  name_buf: [128]byte
  name_len, read_name_err := os.read(os.stdin, name_buf[:])
  if read_name_err != nil
  {
    fmt.eprintln(read_name_err)
    return
  }

  user = com.create_user(string(name_buf[:name_len-1]))

  // --- Connect to server ---------------
  for
  {
    defer mem.clear_arena(&temp_arena)

    dial_err: net.Network_Error
    socket, dial_err = net.dial_tcp(endpoint_str)
    if dial_err != nil
    {
      net.close(socket)
      continue
    }
    else
    {
      packet := com.create_packet(.CLIENT_CONNECTED, nil, {user})
      packet_bytes := com.serialize_packet(&packet, &temp_arena)
      _, send_err := net.send_tcp(socket, packet_bytes)
      if send_err != nil
      {
        fmt.eprintln("Conn error:", send_err)
        continue
      }
      else
      {
        fmt.println("Connected to server on", endpoint_str)

        receive_messages_thread = thread.create(recieve_messages_thread_proc)
        thread.start(receive_messages_thread)
      }

      break
    }
  }

  // --- Client loop ---------------
  for !shutdown
  {
    defer mem.clear_arena(&temp_arena)

    // --- Prompt user for message ---------------
    message_buf: [com.MAX_MESSAGE_SIZE]byte
    message_len, _ := os.read(os.stdin, message_buf[:])

    // --- Send message ---------------
    message := com.create_message(user.id, string(message_buf[:message_len-1]))
    packet := com.create_packet(.MESSAGE_FROM_CLIENT, {message}, nil)
    packet_bytes := com.serialize_packet(&packet, &temp_arena)
    _, send_err := net.send_tcp(socket, packet_bytes)
    if send_err != nil
    {
      fmt.eprintln("Send error:", send_err)
      continue
    }
  }

  thread.join(receive_messages_thread)
}

recieve_messages_thread_proc :: proc(this: ^thread.Thread)
{
  for
  {
    // --- Listen for message ---------------
    packet_bytes: [com.MAX_MESSAGE_SIZE]byte
    bytes_read, recv_err := net.recv_tcp(socket, packet_bytes[:])

    if recv_err != nil
    {
      err, ok := recv_err.(net.TCP_Recv_Error)
      if !(ok && err == .Timeout)
      {
        fmt.eprintln("Recv error:", recv_err)
      }
    }
    else if bytes_read == 0
    {
      fmt.println("Server disconnected.")
      shutdown = true
      break
    }
    else
    {
      packet := com.deserialize_packet(packet_bytes[:bytes_read], &perm_arena)
      #partial switch packet.kind
      {
      case .CLIENT_CONNECTED:
        usr := packet.users[0]

        term.color(.GRAY)
        fmt.print(usr.name)
        fmt.printf(" has entered the chat.\n")
        term.color(.WHITE)
      case .CLIENT_DISCONNECTED:
        usr := packet.users[0]

        term.color(.GRAY)
        fmt.print(usr.name)
        fmt.printf(" has left the chat.\n")
        term.color(.WHITE)
      case .MESSAGE_FROM_SERVER:
        message := packet.messages[0]
        sender := packet.users[0]

        term.color(com.color_to_term_color(sender.color))
        fmt.print(sender.name)
        term.color(.WHITE)
        fmt.printf(": %s\n", message.data)
      }
    }
  }
}
