client: client/main.odin
	./bclient.sh
server:
	odin build ./server -collection:project=.
check_leaks:
	valgrind --leak-check=full --show-leak-kinds=all --track-origins=yes -s ./odin_one
dbg:
	gdb --args ./odin_one
