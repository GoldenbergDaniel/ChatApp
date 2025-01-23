package main

APP_TYPE :: #config(APP_TYPE, "nil")
ENDPOINT :: #config(ENDPOINT, "127.0.0.1:3300")

main :: proc()
{
  /**/ when APP_TYPE == "client" do client_entry()
  else when APP_TYPE == "server" do server_entry()
  else when APP_TYPE == "nil"    do panic("Error: Built with invalid APP_TYPE!")
}
