const std = @import("std");
const zqdm = @import("zqdm").zqdm;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var list: std.ArrayList(u8) = .{};
    try list.appendSlice(allocator, "Hello there! ");
    try list.appendSlice(allocator, "This is a demo of zqdm progress bar in Zig. ");
    try list.appendSlice(allocator, "Enjoy!\n");

    var progress_bar = try zqdm(u8).new(allocator, list.items);
    while (progress_bar.next()) |val| {
        std.Thread.sleep(100000000);
        try progress_bar.write("{c}", .{val.get()});
    }
}
