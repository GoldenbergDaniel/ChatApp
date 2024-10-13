package term

import "core:fmt"

@(private)
current_color: Color_Kind

Color_Kind :: enum
{
  BLACK,
  BLUE,
  GRAY,
  GREEN,
  ORANGE,
  PURPLE,
  RED,
  WHITE,
  YELLOW,
}

Style_Kind :: enum
{
  NONE,
  BOLD,
  ITALIC,
  UNDERLINE,
}

Cursor_Mode :: enum
{
  DEFAULT,
  BLINK,
}

reset :: proc()
{
  fmt.print("\u001b[0m")
}

color :: proc(kind: Color_Kind)
{
  switch kind
  {
  case .BLACK:  fmt.print("\u001b[38;5;16m")
  case .BLUE:   fmt.print("\u001b[38;5;4m")
  case .GRAY:   fmt.print("\u001b[38;5;7m")
  case .GREEN:  fmt.print("\u001b[38;5;2m")
  case .ORANGE: fmt.print("\u001b[38;5;166m")
  case .PURPLE: fmt.print("\u001b[38;5;35m")
  case .RED:    fmt.print("\u001b[38;5;1m")
  case .WHITE:  fmt.print("\u001b[38;5;15m")
  case .YELLOW: fmt.print("\u001b[93m")
  }

  current_color = kind
}

color_as_string :: proc(kind: Color_Kind) -> string
{
  result: string

  switch kind
  {
  case .BLACK:  result = "\u001b[38;5;16m"
  case .BLUE:   result = "\u001b[38;5;4m"
  case .GRAY:   result = "\u001b[38;5;7m"
  case .GREEN:  result = "\u001b[38;5;2m"
  case .ORANGE: result = "\u001b[38;5;166m"
  case .PURPLE: result = "\u001b[38;5;35m"
  case .RED:    result = "\u001b[38;5;1m"
  case .WHITE:  result = "\u001b[38;5;15m"
  case .YELLOW: result = "\u001b[93m"
  }

  return result
}

style :: proc(set: bit_set[Style_Kind])
{
  if .NONE in set
  {
    fmt.print("\u001b[0m")
  }
  else
  {
    if .BOLD in set do fmt.print("\u001b[1m")
    else if .ITALIC in set do fmt.print("\u001b[23m")
    else if .UNDERLINE in set do fmt.print("\u001b[24m")
  }
}

cursor_mode :: proc(mode: Cursor_Mode)
{
  switch mode
  {
  case .DEFAULT: fmt.print("\u001b[0m"); color(current_color)
  case .BLINK:   fmt.print("\u001b[25m")
  }
}
