@echo off
call kill_server.bat
echo Starting Ruby Server...
start /min "Ruby Server" ruby server.rb
echo Server started in new minimized window.
