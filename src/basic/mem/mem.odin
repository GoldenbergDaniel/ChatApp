package mem0

import "base:intrinsics"
import "base:runtime"
import "core:mem"
import "core:mem/virtual"

Allocator       :: runtime.Allocator
Allocator_Error :: runtime.Allocator_Error
Arena           :: virtual.Arena
Arena_Temp      :: virtual.Arena_Temp
Scratch         :: mem.Scratch

KIB :: 1 << 10
MIB :: 1 << 20
GIB :: 1 << 30

GROWING_MIN_SIZE :: virtual.DEFAULT_ARENA_GROWING_MINIMUM_BLOCK_SIZE
STATIC_RES_SIZE  :: virtual.DEFAULT_ARENA_STATIC_RESERVE_SIZE
STATIC_COM_SIZE  :: virtual.DEFAULT_ARENA_STATIC_COMMIT_SIZE

copy :: #force_inline proc "contextless" (dst, src: rawptr, len: int) -> rawptr
{
	intrinsics.mem_copy(dst, src, len)
	return dst
}

set :: #force_inline proc "contextless" (data: rawptr, value: byte, len: int) -> rawptr
{
	return runtime.memset(data, i32(value), len)
}

allocator :: #force_inline proc "contextless" (arena: ^Arena) -> Allocator
{
	return Allocator{
		procedure = virtual.arena_allocator_proc,
		data = arena
	}
}

init_arena_buffer :: proc(arena: ^Arena, buffer: []byte) -> Allocator_Error
{
	return virtual.arena_init_buffer(arena, buffer)
}

init_arena_growing :: proc(arena: ^Arena, 
                           reserved := GROWING_MIN_SIZE) -> Allocator_Error
{
	return virtual.arena_init_growing(arena, uint(reserved))
}

init_arena_static :: proc(arena: ^Arena, 
                          reserved := STATIC_RES_SIZE,
                          committed := STATIC_COM_SIZE) -> Allocator_Error
{
	return virtual.arena_init_static(arena, uint(reserved), uint(committed))
}

clear_arena :: #force_inline proc(arena: ^Arena)
{
	free_all(allocator(arena))
}

destroy_arena :: #force_inline proc(arena: ^Arena)
{
	virtual.arena_destroy(arena)
}

begin_temp :: #force_inline proc(arena: ^Arena) -> Arena_Temp
{
	return virtual.arena_temp_begin(arena)
}

end_temp :: #force_inline proc(temp: Arena_Temp)
{
	virtual.arena_temp_end(temp)
}

init_scratch :: proc(scratch: ^Scratch, size: int, arena: ^Arena)
{
	mem.scratch_init(scratch, size, allocator(arena))
}
