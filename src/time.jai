// Both `month`, `day` and `weekday` starts from 0.
get_weekday :: (year:int, month:int, day:int) -> int {
	t := int.[0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4];
	if month < 2 {
		year -= 1;
	}
	day += 1;
	return (year + year/4 - year/100 + year/400 + t[month] + day) % 7;
}
is_date_valid :: (year:int, month:int, day:int) -> bool {
	if month < 0 || month > 11 return false;

	days_in_months :: int.[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

	days_in_month := days_in_months[month];
	if is_leap_year(year) && month == 1 { // February
		days_in_month = 29;
	}

	if day < 0 || day >= days_in_month return false;

	return true;
}

is_time_valid :: (year:int, month:int, day:int) -> bool {
	if month < 0 || month > 11 return false;

	days_in_months :: int.[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

	days_in_month := days_in_months[month];
	if is_leap_year(year) && month == 1 { // February
		days_in_month = 29;
	}

	if day < 0 || day >= days_in_month return false;

	return true;
}

is_leap_year :: (year: int) -> bool {
	if year % 400 == 0 return true;
	if year % 100 == 0 return false;
	if year % 4 == 0 return true;
	return false;
}

get_tomorrow :: (calendar: Calendar_Time) -> Calendar_Time {
	result := calendar;
	result.day_of_month_starting_at_0 += 1;
	if result.day_of_month_starting_at_0 > get_days_in_month(result.year, result.month_starting_at_0) {
		result.day_of_month_starting_at_0 = 0;
		result.month_starting_at_0 += 1;
		if result.month_starting_at_0 > 11 {
			result.month_starting_at_0 = 1;
			result.year += 1;
		}
	}
	result.day_of_week_starting_at_0 = xx get_weekday(result);
	return result;
}

#scope_file;
get_weekday :: inline (ct: Calendar_Time) -> int {
	return get_weekday(ct.year, ct.month_starting_at_0, ct.day_of_month_starting_at_0);
}

get_days_in_month :: (year: int, month: int) -> int {
	days_in_months :: int.[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
	days_in_month := days_in_months[month];
	if is_leap_year(year) && month == 1 { // February
		days_in_month = 29;
	}
	return days_in_month;
}
