package common

import "core:fmt"
import "core:math/rand"
import "core:strings"

import "src:basic/bytes"
import "src:basic/mem"
import "src:term"

MAX_CLIENT_CONNECTIONS :: 10

// Packet ////////////////////////////////////////////////////////////////////////////////

Packet :: struct
{
  kind: Packet_Kind,
  message_count: u32,
  messages: []Message,
  user_count: u32,
  users: []User,
}

Packet_Kind :: enum u8
{
  MESSAGE_FROM_SERVER,
  MESSAGE_FROM_CLIENT,
  CLIENT_CONNECTED,
  CLIENT_DISCONNECTED,
}

MAX_PACKET_SIZE :: mem.MIB

create_packet :: proc(kind: Packet_Kind, messages: []Message, users: []User) -> Packet
{
  result: Packet
  result.kind = kind
  result.message_count = cast(u32) len(messages)
  result.messages = messages
  result.user_count = cast(u32) len(users)
  result.users = users

  return result
}

serialize_packet :: proc(packet: ^Packet, arena: ^mem.Arena) -> []byte
{
  result, err := make([]byte, mem.MIB, mem.allocator(arena))
  if err != nil do fmt.println(err)

  temp := mem.begin_temp(arena)

  buffer := bytes.create_buffer(result, .BE)
  bytes.write_u8(&buffer, u8(packet.kind))
  
  bytes.write_u32(&buffer, packet.message_count)
  for i: u32; i < packet.message_count; i += 1
  {
    bytes.write_bytes(&buffer, bytes_from_message(packet.messages[i], temp.arena))
  }

  bytes.write_u32(&buffer, packet.user_count)
  for i: u32; i < packet.user_count; i += 1
  {
    bytes.write_bytes(&buffer, bytes_from_user(packet.users[i], temp.arena))
  }

  mem.end_temp(temp)

  return result[:buffer.w_pos]
}

deserialize_packet :: proc(buf: []byte, arena: ^mem.Arena) -> Packet
{
  result: Packet

  buffer := bytes.create_buffer(buf, .BE)
  result.kind = cast(Packet_Kind) bytes.read_u8(&buffer)

  message_count := bytes.read_u32(&buffer)
  result.message_count = message_count
  result.messages = make([]Message, message_count, mem.allocator(arena))
  for i in 0..<message_count
  {
    message, bytes_read := message_from_bytes(buffer.data[buffer.r_pos:], arena)
    result.messages[i] = message
    buffer.r_pos += bytes_read
  }

  user_count := bytes.read_u32(&buffer)
  result.user_count = user_count
  result.users = make([]User, user_count, mem.allocator(arena))
  for i in 0..<user_count
  {
    user, bytes_read := user_from_bytes(buffer.data[buffer.r_pos:], arena)
    result.users[i] = user
    buffer.r_pos += bytes_read
  }

  return result
}


// User //////////////////////////////////////////////////////////////////////////////////


User_ID :: u32

User :: struct
{
  id: User_ID,
  color: Color_Kind,
  name_len: u32,
  name: string,
}

MAX_USER_SIZE :: 128

create_user :: proc(name: string, color: Color_Kind = .BLUE) -> User
{
  result: User
  result.id = rand.uint32()
  result.name_len = cast(u32) len(name)
  result.name = name

  return result
}

@(private)
bytes_from_user :: proc(user: User, arena: ^mem.Arena) -> []byte
{
  result := make([]byte, MAX_USER_SIZE, mem.allocator(arena))

  buffer := bytes.create_buffer(result, .BE)
  bytes.write_u32(&buffer, user.id)
  bytes.write_u8(&buffer, cast(u8) user.color)
  bytes.write_u32(&buffer, user.name_len)
  bytes.write_bytes(&buffer, transmute([]byte) user.name[:user.name_len])

  return result[:buffer.w_pos]
}

@(private)
user_from_bytes :: proc(buf: []byte, arena: ^mem.Arena) -> (User, int)
{
  result: User

  buffer := bytes.create_buffer(buf, .BE)
  result.id = bytes.read_u32(&buffer)
  result.color = cast(Color_Kind) bytes.read_u8(&buffer)
  result.name_len = bytes.read_u32(&buffer)
  result.name = cast(string) bytes.read_bytes(&buffer, int(result.name_len))
  result.name = strings.clone(result.name, mem.allocator(arena))

  return result, buffer.r_pos
}


// Message ///////////////////////////////////////////////////////////////////////////////


Message :: struct
{
  sender_id: User_ID,
  data_len: u32,
  data: string,
}

MAX_MESSAGE_SIZE :: 128

create_message :: proc(sender_id: User_ID, data: string) -> Message
{
  result: Message
  result.sender_id = sender_id
  result.data_len = cast(u32) len(data)
  result.data = data

  return result
}

@(private)
bytes_from_message :: proc(message: Message, arena: ^mem.Arena) -> []byte
{
  result := make([]byte, MAX_MESSAGE_SIZE, mem.allocator(arena))

  buffer := bytes.create_buffer(result, .BE)
  bytes.write_u32(&buffer, message.sender_id)
  bytes.write_u32(&buffer, message.data_len)
  bytes.write_bytes(&buffer, transmute([]byte) message.data[:message.data_len])

  return result[:buffer.w_pos]
}

@(private)
message_from_bytes :: proc(buf: []byte, arena: ^mem.Arena) -> (Message, int)
{
  result: Message

  buffer := bytes.create_buffer(buf, .BE)
  result.sender_id = bytes.read_u32(&buffer)
  result.data_len = bytes.read_u32(&buffer)
  result.data = cast(string) bytes.read_bytes(&buffer, int(result.data_len))
  result.data = strings.clone(result.data, mem.allocator(arena))

  return result, buffer.r_pos
}


// Util //////////////////////////////////////////////////////////////////////////////////


Color_Kind :: enum u8
{
  BLUE,
  GREEN,
  ORANGE,
  PURPLE,
  YELLOW,
}

color_to_term_color :: proc(color: Color_Kind) -> term.Color_Kind
{
  result: term.Color_Kind

  switch color
  {
  case .BLUE:   result = .BLUE
  case .GREEN:  result = .GREEN
  case .ORANGE: result = .ORANGE
  case .PURPLE: result = .PURPLE
  case .YELLOW: result = .YELLOW
  }

  return result
}
