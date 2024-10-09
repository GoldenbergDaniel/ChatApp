package common

import "core:mem"
import "core:strings"

import "src:term"

// User //////////////////////////////////////////////////////////////////////////////////


UserID :: u32

User :: struct #packed
{
  id: UserID,
  color: ColorKind,
  name: string,
}

MAX_USER_SIZE    :: 128

bytes_from_user :: proc(user: User, arena: mem.Allocator) -> []byte
{
  result := make([]byte, MAX_USER_SIZE, arena)
  result_pos: int

  id_bytes := transmute([size_of(user.id)]byte) user.id
  for b in id_bytes
  {
    result[result_pos] = b
    result_pos += 1
  }

  result[result_pos] = cast(byte) user.color
  result_pos += 1

  for b in user.name
  {
    result[result_pos] = cast(byte) b
    result_pos += 1
  }

  return result
}

user_from_bytes :: proc(bytes: []byte, arena: mem.Allocator) -> User
{
  result: User
  result.id = u32_from_bytes(bytes[:4])
  result.color= cast(ColorKind) u8_from_bytes(bytes[4:5])
  result.name = string_from_bytes(bytes[5:], arena)

  return result
}


// Message ///////////////////////////////////////////////////////////////////////////////


Message :: struct #packed
{
  sender: UserID,
  data: string,
}

MAX_MESSAGE_SIZE :: 128

bytes_from_message :: proc(message: Message, arena: mem.Allocator) -> []byte
{
  result := make([]byte, size_of(UserID) + len(message.data), arena)
  result_pos: int

  id_bytes := transmute([size_of(UserID)]byte) message.sender
  for b in id_bytes
  {
    result[result_pos] = b
    result_pos += 1
  }

  for b in message.data
  {
    result[result_pos] = cast(byte) b
    result_pos += 1
  }

  return result
}

message_from_bytes :: proc(bytes: []byte, arena: mem.Allocator) -> Message
{
  result: Message
  result.sender = u32_from_bytes(bytes[:4])
  result.data = string_from_bytes(bytes[4:], arena)

  return result
}


// Util //////////////////////////////////////////////////////////////////////////////////


@(private)
struct_asserts :: proc(user: User, msg: Message)
{
  #assert(size_of(User) == 
            size_of(user.id) + 
            size_of(user.name) + 
            size_of(user.color))

  #assert(size_of(Message) == 
            size_of(msg.sender) + 
            size_of(msg.data))
}

u8_from_bytes :: proc(bytes: []byte) -> u8
{
  result: u8
  
  size := size_of(u8)
  assert(len(bytes) == size)

  for i in 0..<size
  {
    result |= u8(bytes[i]) << (uint(size-i-1) * 8)
  }

  return result
}

u32_from_bytes :: proc(bytes: []byte) -> u32
{
  result: u32
  
  size := size_of(u32)
  assert(len(bytes) == size)

  for i in 0..<size
  {
    result |= u32(bytes[i]) << (uint(size-i-1) * 8)
  }

  return result
}

string_from_bytes :: proc(bytes: []byte, arena: mem.Allocator) -> string
{
  return strings.clone_from_bytes(bytes, arena)
}

ColorKind :: enum u8
{
  BLUE,
  GREEN,
  ORANGE,
  PURPLE,
  YELLOW,
}

color_to_term_color :: proc(color: ColorKind) -> term.ColorKind
{
  result: term.ColorKind

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
