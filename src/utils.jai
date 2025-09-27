region_timer :: (tag:string="") #expand {
	begin := current_time_consensus();
	`defer {
		end := current_time_consensus();
		d := end - begin;
		milliseconds := (d/1_000_000_000_000).low;
		if milliseconds == 0 {
			us := (d/1_000_000_000).low;
			print("%: % us.\n", tag, us);
		} else {
			print("%: % ms.\n", tag, milliseconds);
		}
	}
}

MiniTimer :: struct {
	time : Apollo_Time;
	tag  : string;
}
timer_begin :: inline (tag: string) -> MiniTimer {
	return .{current_time_consensus(), tag};
}
timer_end :: inline (t: *MiniTimer) {
	d := current_time_consensus() - t.time;
	milliseconds := (d/1_000_000_000_000).low;
	if milliseconds == 0 {
		us := (d/1_000_000_000).low;
		print("%: % us.\n", t.tag, us);
	} else {
		print("%: % ms.\n", t.tag, milliseconds);
	}
}

string_by_line :: (s: *string, code: Code, flags: For_Flags) #expand {
	#assert flags == 0 "Doesn't support flags.";
	idx : int;
	current : string;
	current.data = s.data;

	for v,n :s.* {
		if v == "\n" {
			`it := current;
			`it_index := idx;
			#insert code;
			current.data = s.data + n + 1;
			current.count = 0;
			idx += 1;
		} else {
			current.count += 1;
		}
	}
}

find_substring :: (s: string, substring: string) -> s64 {
	point :s64= 0;
	for i: 0..s.count-1 {
		if s[i] == substring[point] {
			point += 1;
			if point == substring.count {
				return i - point + 1;
			}
		} else {
			point = 0;
		}
	}
	return -1;
}
find_substrings :: (s: string, substring: string, allocator:=context.allocator) -> []s64 {
	push_allocator(allocator);
	point :s64= 0;
	results :[..]s64;
	for i: 0..s.count-1 {
		if s[i] == substring[point] {
			point += 1;
			if point == substring.count {
				array_add(*results, i - point + 1);
				point = 0;
			}
		} else {
			point = 0;
		}
	}
	return results;
}

