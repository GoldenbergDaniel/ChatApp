package main

APP_TYPE :: #config(APP_TYPE, "nil")

main :: proc()
{
  /**/ when APP_TYPE == "client" do client_entry()
  else when APP_TYPE == "server" do server_entry()
}
