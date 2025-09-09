init_console :: () {
	#if OS == .WINDOWS {
		#import "Windows";
		SetConsoleCP(65001);
		SetConsoleOutputCP(65001);
	}
}
