using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace HearHere.Shared.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddIdentityProviderToUser : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "identity_provider",
                table: "users",
                type: "varchar(20)",
                nullable: false,
                defaultValue: "entra");

            migrationBuilder.AddCheckConstraint(
                name: "chk_users_identity_provider",
                table: "users",
                sql: "identity_provider IN ('entra', 'google', 'apple')");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "chk_users_identity_provider",
                table: "users");

            migrationBuilder.DropColumn(
                name: "identity_provider",
                table: "users");
        }
    }
}
