using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace HearHere.Shared.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddApnsTokenToUser : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "apns_token",
                table: "users",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "apns_token",
                table: "users");
        }
    }
}
