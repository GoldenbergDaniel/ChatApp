package common

import "core:mem"
import "core:strings"

UserID :: u32

User :: struct #packed
{
  id: UserID,
  name: string,
}

bytes_from_user :: proc(user: User, arena: mem.Allocator) -> []byte
{
  result := make([]byte, size_of(user.id) + len(user.name), arena)
  result_pos: int

  id_bytes := transmute([size_of(user.id)]byte) user.id
  for b in id_bytes
  {
    result[result_pos] = b
    result_pos += 1
  }

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
  result.name = string_from_bytes(bytes[4:], arena)

  return result
}

Message :: struct #packed
{
  sender: UserID,
  data: string,
}

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
