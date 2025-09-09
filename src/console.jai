#import "Windows";

init_console :: () {
	#if OS == .WINDOWS {
		SetConsoleCP(65001);
		SetConsoleOutputCP(65001);
	}
}

read_stdin :: ($invisible:bool=false, $buffer_size:int=1024, allocator:= context.allocator) -> string {
	push_allocator(allocator);
	#assert buffer_size % 1024 == 0;
	#if OS == .WINDOWS {
		stdin = ifx stdin!=null else GetStdHandle( STD_INPUT_HANDLE );
		// setup console mode
		orig_mode : DWORD;
		GetConsoleMode(stdin, *orig_mode);

		#if invisible {
			SetConsoleMode(stdin, orig_mode & ~ENABLE_ECHO_INPUT);
		}
		defer #if invisible {// recover console mode
			SetConsoleMode(stdin, orig_mode);
		}

		MAX_BYTES_TO_READ :: 1024;
		temp : [MAX_BYTES_TO_READ] u8;
		result: string = ---;
		bytes_read : s32;

		if !ReadConsoleA( stdin, temp.data, xx temp.count, *bytes_read )
			return "";
		bytes_read -= 2; // remove \r\n

		result.data  = alloc(bytes_read);
		result.count = bytes_read;
		memcpy(result.data, temp.data, bytes_read);
		return result;
	}
}

#scope_file;

kernel32 :: #library,system "kernel32";

stdin, stdout  : HANDLE;

ReadConsoleA  :: (
	hConsoleHandle: HANDLE, 
	buff : *u8, 
	chars_to_read : s32,  
	chars_read : *s32, 
	lpInputControl := *void 
) -> bool #foreign kernel32;

ENABLE_ECHO_INPUT :DWORD: 0x0004;
