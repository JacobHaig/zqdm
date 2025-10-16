const std = @import("std");
const builtin = @import("builtin");
// const zqdm = @import("zqdm");
const unicode = @import("std").unicode;
const Io = @import("std").Io;

pub fn zqdm(comptime T: type) type {
    const Zqdm = struct {
        const Self = @This();

        filled_char: []const u8 = "█",
        empty_char: []const u8 = "░",

        slice: []const T,
        element: usize,
        terminal_width: usize,

        allocator: std.mem.Allocator,
        stdout_backlog: std.ArrayList(u8),
        start_time: i64 = undefined,

        stderr: *Io.Writer = undefined,

        pub fn new(allocator: std.mem.Allocator, slice: []const T) Self {
            var terminal_width: usize = undefined;

            switch (builtin.os.tag) {
                .windows => {
                    // Enable UTF-8 output - required for windows terminal to display unicode characters correctly
                    _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);

                    // Get terminal width
                    var buf: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
                    _ = std.os.windows.kernel32.GetConsoleScreenBufferInfo(std.fs.File.stdout().handle, &buf);
                    terminal_width = @intCast(buf.srWindow.Right - buf.srWindow.Left + 1);
                },
                else => @panic("Only Windows is supported for now. Feel free to contribute!"),
            }

            return Self{
                .slice = slice,
                .element = 0,
                .terminal_width = terminal_width,
                .allocator = allocator,
                .stdout_backlog = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable,
                .start_time = std.time.milliTimestamp(),
            };
        }

        pub fn get(self: *Self) T {
            return self.slice[self.element - 1];
        }

        pub fn next(self: *Self) ?*Self {
            if (self.element >= self.slice.len) return null;
            self.element += 1;

            self.display();

            return self;
        }

        pub fn display(self: *Self) void {
            var stderr_buffer: [1024]u8 = undefined;
            var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
            const stderr = &stderr_writer.interface;
            self.stderr = stderr;

            const elapsed_milliseconds = std.time.milliTimestamp() - self.start_time;

            // print a carriage return to overwrite the previous line
            self.stderr.print("\r", .{}) catch unreachable;

            const print_percentage_width: usize = 7; // Width for percentage display (e.g., "100.00%")
            const print_estimated_time_width: usize = 35; // Width for estimated time display (e.g., " 13/13 [00:01<00:00,  9.94it/s]")

            const percentage: f32 = @as(f32, @floatFromInt(self.element)) / @as(f32, @floatFromInt(self.slice.len));

            self.print_percentage(percentage);
            self.print_progress_bar(percentage, self.terminal_width - print_percentage_width - print_estimated_time_width);
            self.print_estimated_time_remaining(percentage, elapsed_milliseconds);

            // If we're done iterating, print a newline to move the cursor to the next line
            if (self.element == self.slice.len) {
                self.stderr.print("\n", .{}) catch unreachable;
            }

            self.stderr.flush() catch unreachable;
        }

        fn print_percentage(self: *Self, percentage: f32) void {
            // Print percentage with 2 decimal places, right-aligned in a field of width 7
            self.stderr.print("{d:>6.2}%", .{percentage * 100.0}) catch unreachable;
        }

        pub fn print_estimated_time_remaining(self: *Self, percentage: f32, elapsed_milliseconds: i64) void {
            // 13/13 [00:01<00:00,  9.94it/s]
            // Print elapsed time, estimated remaining time, and iteration speed

            const index = self.element;
            const total = self.slice.len;

            const elapsed_seconds = @divTrunc(elapsed_milliseconds, 1000);
            const elapsed_minutes = @divTrunc(elapsed_seconds, 60);
            const elapsed_hours = @divTrunc(elapsed_minutes, 60);

            var remaining_seconds: i64 = 0;
            if (percentage > 0.0) {
                const estimated_total_time: i64 = @intFromFloat(@as(f32, @floatFromInt(elapsed_milliseconds)) / percentage);
                const estimated_remaining_time = estimated_total_time - elapsed_milliseconds;
                remaining_seconds = @divTrunc(estimated_remaining_time, 1000);
            }
            const remaining_minutes = @divTrunc(remaining_seconds, 60);
            const remaining_hours = @divTrunc(remaining_minutes, 60);
            const speed: f32 = if (elapsed_seconds > 0) @as(f32, @floatFromInt(index)) / @as(f32, @floatFromInt(elapsed_seconds)) else 0.0;

            self.stderr.print(" {d}/{d} [{d:02}:{d:02}< {d:02}:{d:02}, {d:.2}it/s]", .{
                index,
                total,
                elapsed_hours,
                @mod(elapsed_minutes, 60),
                remaining_hours,
                @mod(remaining_minutes, 60),
                speed,
            }) catch unreachable;
        }

        fn print_progress_bar(self: *Self, percentage: f32, progress_bar_width: usize) void {
            // Correct for the brackets width
            const bracket_width: usize = 4; // Width for the brackets " [" and "] "
            const corrected_progress_bar_width = progress_bar_width - bracket_width;

            const progress_width_f32: f32 = @floatFromInt(corrected_progress_bar_width);
            const print_width: usize = @intFromFloat(percentage * progress_width_f32);

            self.stderr.print(" [", .{}) catch unreachable;

            // Draw the filled part of the progress bar
            for (0..print_width) |_| self.stderr.print("{s}", .{self.filled_char}) catch unreachable;
            // Draw the empty part of the progress bar
            for (print_width..corrected_progress_bar_width) |_| self.stderr.print("{s}", .{self.empty_char}) catch unreachable;

            self.stderr.print("] ", .{}) catch unreachable;
        }

        /// Like tqdm.write: prints a message above the progress bar, then redraws the bar.
        pub fn write(self: *Self, comptime fmt: []const u8, args: anytype) !void {
            // Write the user message to stdout_backlog, once its done iterating we'll print it out
            const msg = try std.fmt.allocPrint(self.allocator, fmt, args);
            _ = try self.stdout_backlog.appendSlice(self.allocator, msg);

            // If we're done iterating, print the backlog and clear it
            if (self.element == self.slice.len) {

                // Print to stdout
                var stdout_buffer: [1024]u8 = undefined;
                var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
                const stdout = &stdout_writer.interface;

                stdout.print("{s}", .{self.stdout_backlog.items}) catch unreachable;
                stdout.flush() catch unreachable;

                self.stdout_backlog.deinit(self.allocator);
                self.stdout_backlog = try std.ArrayList(u8).initCapacity(self.allocator, 0);
            }
            return;
        }
    };

    return Zqdm;
}
