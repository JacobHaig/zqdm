const std = @import("std");
const zqdm = @import("zqdm").zqdm;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const slice: []const u8 = "Hello there! This is a demo of zqdm progress bar in Zig. Enjoy!";

    var progress_bar = zqdm(u8).new(allocator, slice);
    while (progress_bar.next()) |val| {
        std.Thread.sleep(100000000);
        try progress_bar.write("{c}", .{val.get()});
    }
}
