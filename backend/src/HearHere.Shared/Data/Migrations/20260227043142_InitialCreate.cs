using System;
using Microsoft.EntityFrameworkCore.Migrations;
using NetTopologySuite.Geometries;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace HearHere.Shared.Data.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterDatabase()
                .Annotation("Npgsql:PostgresExtension:postgis", ",,");

            migrationBuilder.CreateTable(
                name: "tags",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityAlwaysColumn),
                    name = table.Column<string>(type: "varchar(50)", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_tags", x => x.id);
                    table.CheckConstraint("chk_tags_name_lowercase", "name = lower(name)");
                });

            migrationBuilder.CreateTable(
                name: "users",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    external_id = table.Column<string>(type: "text", nullable: false),
                    display_name = table.Column<string>(type: "varchar(100)", nullable: false),
                    email = table.Column<string>(type: "varchar(255)", nullable: true),
                    avatar_blob_key = table.Column<string>(type: "text", nullable: true),
                    role = table.Column<string>(type: "varchar(20)", nullable: false, defaultValue: "user"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_users", x => x.id);
                    table.CheckConstraint("chk_users_role", "role IN ('user', 'moderator', 'admin')");
                });

            migrationBuilder.CreateTable(
                name: "recordings",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    subject = table.Column<string>(type: "varchar(200)", nullable: false),
                    description = table.Column<string>(type: "text", nullable: true),
                    location = table.Column<Point>(type: "geography (point, 4326)", nullable: false),
                    location_name = table.Column<string>(type: "varchar(300)", nullable: true),
                    city = table.Column<string>(type: "varchar(100)", nullable: true),
                    region = table.Column<string>(type: "varchar(100)", nullable: true),
                    country = table.Column<string>(type: "varchar(100)", nullable: true),
                    audio_blob_key = table.Column<string>(type: "text", nullable: false),
                    audio_format = table.Column<string>(type: "varchar(10)", nullable: false, defaultValue: "aac"),
                    duration_sec = table.Column<int>(type: "integer", nullable: false),
                    file_size_bytes = table.Column<int>(type: "integer", nullable: true),
                    status = table.Column<string>(type: "varchar(30)", nullable: false, defaultValue: "pending_moderation"),
                    transcript = table.Column<string>(type: "text", nullable: true),
                    moderation_scores = table.Column<string>(type: "jsonb", nullable: true),
                    category = table.Column<string>(type: "varchar(50)", nullable: true),
                    play_count = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    like_count = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    deleted_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_recordings", x => x.id);
                    table.CheckConstraint("chk_recordings_audio_format", "audio_format IN ('aac', 'm4a', 'mp3')");
                    table.CheckConstraint("chk_recordings_category", "category IS NULL OR category IN ('history', 'nature', 'architecture', 'culture', 'personal', 'food', 'music', 'art', 'politics', 'science', 'other')");
                    table.CheckConstraint("chk_recordings_duration", "duration_sec > 0 AND duration_sec <= 300");
                    table.CheckConstraint("chk_recordings_status", "status IN ('pending_upload', 'pending_moderation', 'pending_review', 'approved', 'rejected')");
                    table.ForeignKey(
                        name: "FK_recordings_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "likes",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    recording_id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_likes", x => x.id);
                    table.ForeignKey(
                        name: "FK_likes_recordings_recording_id",
                        column: x => x.recording_id,
                        principalTable: "recordings",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_likes_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "moderation_records",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    recording_id = table.Column<Guid>(type: "uuid", nullable: false),
                    action = table.Column<string>(type: "varchar(30)", nullable: false),
                    actor_type = table.Column<string>(type: "varchar(20)", nullable: false),
                    actor_id = table.Column<string>(type: "text", nullable: true),
                    from_status = table.Column<string>(type: "varchar(30)", nullable: false),
                    to_status = table.Column<string>(type: "varchar(30)", nullable: false),
                    scores = table.Column<string>(type: "jsonb", nullable: true),
                    reason = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_moderation_records", x => x.id);
                    table.CheckConstraint("chk_moderation_action", "action IN ('auto_approve', 'auto_reject', 'escalate_to_review', 'manual_approve', 'manual_reject')");
                    table.CheckConstraint("chk_moderation_actor_type", "actor_type IN ('system', 'moderator', 'admin')");
                    table.ForeignKey(
                        name: "FK_moderation_records_recordings_recording_id",
                        column: x => x.recording_id,
                        principalTable: "recordings",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "plays",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    recording_id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    duration_sec = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    completed = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_plays", x => x.id);
                    table.ForeignKey(
                        name: "FK_plays_recordings_recording_id",
                        column: x => x.recording_id,
                        principalTable: "recordings",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_plays_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "recording_tags",
                columns: table => new
                {
                    recording_id = table.Column<Guid>(type: "uuid", nullable: false),
                    tag_id = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_recording_tags", x => new { x.recording_id, x.tag_id });
                    table.ForeignKey(
                        name: "FK_recording_tags_recordings_recording_id",
                        column: x => x.recording_id,
                        principalTable: "recordings",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_recording_tags_tags_tag_id",
                        column: x => x.tag_id,
                        principalTable: "tags",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "reports",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    recording_id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    reason_code = table.Column<string>(type: "varchar(30)", nullable: false),
                    description = table.Column<string>(type: "text", nullable: true),
                    status = table.Column<string>(type: "varchar(20)", nullable: false, defaultValue: "submitted"),
                    resolved_by = table.Column<Guid>(type: "uuid", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    resolved_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_reports", x => x.id);
                    table.CheckConstraint("chk_reports_reason_code", "reason_code IN ('hate_speech', 'harassment', 'violence', 'sexual_content', 'spam', 'misinformation', 'other')");
                    table.CheckConstraint("chk_reports_status", "status IN ('submitted', 'reviewing', 'resolved_removed', 'resolved_dismissed')");
                    table.ForeignKey(
                        name: "FK_reports_recordings_recording_id",
                        column: x => x.recording_id,
                        principalTable: "recordings",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_reports_users_resolved_by",
                        column: x => x.resolved_by,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_reports_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_likes_recording_id",
                table: "likes",
                column: "recording_id");

            migrationBuilder.CreateIndex(
                name: "uq_likes_user_recording",
                table: "likes",
                columns: new[] { "user_id", "recording_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "idx_moderation_records_recording_id",
                table: "moderation_records",
                columns: new[] { "recording_id", "created_at" });

            migrationBuilder.CreateIndex(
                name: "idx_plays_recording_id",
                table: "plays",
                column: "recording_id");

            migrationBuilder.CreateIndex(
                name: "idx_plays_user_id",
                table: "plays",
                columns: new[] { "user_id", "created_at" },
                descending: new[] { false, true });

            migrationBuilder.CreateIndex(
                name: "idx_recording_tags_tag_id",
                table: "recording_tags",
                column: "tag_id");

            migrationBuilder.CreateIndex(
                name: "idx_recordings_location",
                table: "recordings",
                column: "location")
                .Annotation("Npgsql:IndexMethod", "gist");

            migrationBuilder.CreateIndex(
                name: "idx_recordings_pending_review",
                table: "recordings",
                column: "created_at",
                filter: "status = 'pending_review' AND deleted_at IS NULL");

            migrationBuilder.CreateIndex(
                name: "idx_recordings_status_approved",
                table: "recordings",
                column: "status",
                filter: "status = 'approved' AND deleted_at IS NULL");

            migrationBuilder.CreateIndex(
                name: "idx_recordings_user_id",
                table: "recordings",
                columns: new[] { "user_id", "created_at" },
                descending: new[] { false, true },
                filter: "deleted_at IS NULL");

            migrationBuilder.CreateIndex(
                name: "idx_reports_status_open",
                table: "reports",
                column: "created_at",
                filter: "status IN ('open', 'reviewing')");

            migrationBuilder.CreateIndex(
                name: "IX_reports_recording_id",
                table: "reports",
                column: "recording_id");

            migrationBuilder.CreateIndex(
                name: "IX_reports_resolved_by",
                table: "reports",
                column: "resolved_by");

            migrationBuilder.CreateIndex(
                name: "IX_reports_user_id",
                table: "reports",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "uq_tags_name",
                table: "tags",
                column: "name",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "uq_users_external_id",
                table: "users",
                column: "external_id",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "likes");

            migrationBuilder.DropTable(
                name: "moderation_records");

            migrationBuilder.DropTable(
                name: "plays");

            migrationBuilder.DropTable(
                name: "recording_tags");

            migrationBuilder.DropTable(
                name: "reports");

            migrationBuilder.DropTable(
                name: "tags");

            migrationBuilder.DropTable(
                name: "recordings");

            migrationBuilder.DropTable(
                name: "users");
        }
    }
}
