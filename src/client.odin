package main

import "core:fmt"
import "core:net"
import "core:thread"
import "core:os"

import "src:basic/mem"
import "src:term"

@(private="file")
perm_arena: mem.Arena

socket: net.TCP_Socket
user: User
receive_messages_thread: ^thread.Thread
shutdown: bool
connected: bool

client_entry :: proc()
{
  // - Prompt user's name ---
  fmt.print("Display name: ")
  name_buf: [128]byte
  name_len, read_name_err := os.read(os.stdin, name_buf[:])
  if read_name_err != nil
  {
    fmt.eprintln(read_name_err)
    return
  }

  user = create_user(string(name_buf[:name_len-1]))

  // - Client loop ---
  for !shutdown
  {
    temp := mem.begin_temp(mem.get_scratch())
    defer mem.end_temp(temp)

    if !connected
    {
      try_connect_to_server()
    }

    // - Prompt user for message ---
    message_buf: [MAX_MESSAGE_SIZE]byte
    message_len, _ := os.read(os.stdin, message_buf[:])
    if message_len <= 0 do continue

    // - Send message ---
    message := create_message(user.id, string(message_buf[:message_len-1]))
    packet := create_packet(.MESSAGE_FROM_CLIENT, {message}, nil)
    packet_bytes := serialize_packet(&packet, temp.arena)
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
    // - Listen for message ---
    packet_bytes: [MAX_MESSAGE_SIZE]byte
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
      connected = false
      break
    }
    else
    {
      packet := deserialize_packet(packet_bytes[:bytes_read], &perm_arena)
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

        term.color(color_to_term_color(sender.color))
        fmt.print(sender.name)
        term.color(.WHITE)
        fmt.printf(": %s\n", message.data)
      }
    }
  }
}

try_connect_to_server :: proc()
{
  temp := mem.begin_temp(mem.get_scratch())
  defer mem.end_temp(temp)

  dial_err: net.Network_Error
  socket, dial_err = net.dial_tcp(ENDPOINT)
  if dial_err != nil
  {
    net.close(socket)
    return
  }
  else
  {
    packet := create_packet(.CLIENT_CONNECTED, nil, {user})
    packet_bytes := serialize_packet(&packet, temp.arena)
    _, send_err := net.send_tcp(socket, packet_bytes)
    if send_err != nil
    {
      fmt.eprintln("Connection error:", send_err)
      return
    }
    else
    {
      fmt.println("Connected to server on", ENDPOINT)
      connected = true
      receive_messages_thread = thread.create(recieve_messages_thread_proc)
      thread.start(receive_messages_thread)
    }
  }
}
