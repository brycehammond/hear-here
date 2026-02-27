using HearHere.Shared.Data.Entities;
using Microsoft.EntityFrameworkCore;

namespace HearHere.Shared.Data;

public class HearHereDbContext : DbContext
{
    public HearHereDbContext(DbContextOptions<HearHereDbContext> options)
        : base(options)
    {
    }

    public DbSet<User> Users => Set<User>();
    public DbSet<Recording> Recordings => Set<Recording>();
    public DbSet<ModerationRecord> ModerationRecords => Set<ModerationRecord>();
    public DbSet<Play> Plays => Set<Play>();
    public DbSet<Like> Likes => Set<Like>();
    public DbSet<Report> Reports => Set<Report>();
    public DbSet<Tag> Tags => Set<Tag>();
    public DbSet<RecordingTag> RecordingTags => Set<RecordingTag>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        ConfigureUser(modelBuilder);
        ConfigureRecording(modelBuilder);
        ConfigureModerationRecord(modelBuilder);
        ConfigurePlay(modelBuilder);
        ConfigureLike(modelBuilder);
        ConfigureReport(modelBuilder);
        ConfigureTag(modelBuilder);
        ConfigureRecordingTag(modelBuilder);
    }

    private static void ConfigureUser(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<User>(entity =>
        {
            entity.ToTable("users", t =>
            {
                t.HasCheckConstraint(
                    "chk_users_role",
                    "role IN ('user', 'moderator', 'admin')");
            });

            entity.HasKey(e => e.Id);

            entity.Property(e => e.Id)
                .HasColumnName("id")
                .HasDefaultValueSql("gen_random_uuid()");

            entity.Property(e => e.ExternalId)
                .HasColumnName("external_id")
                .HasColumnType("text")
                .IsRequired();

            entity.Property(e => e.DisplayName)
                .HasColumnName("display_name")
                .HasColumnType("varchar(100)")
                .IsRequired();

            entity.Property(e => e.Email)
                .HasColumnName("email")
                .HasColumnType("varchar(255)");

            entity.Property(e => e.AvatarBlobKey)
                .HasColumnName("avatar_blob_key")
                .HasColumnType("text");

            entity.Property(e => e.Role)
                .HasColumnName("role")
                .HasColumnType("varchar(20)")
                .HasDefaultValue("user")
                .IsRequired();

            entity.Property(e => e.CreatedAt)
                .HasColumnName("created_at")
                .HasDefaultValueSql("now()")
                .IsRequired();

            entity.Property(e => e.UpdatedAt)
                .HasColumnName("updated_at")
                .HasDefaultValueSql("now()")
                .IsRequired();

            entity.HasIndex(e => e.ExternalId)
                .IsUnique()
                .HasDatabaseName("uq_users_external_id");
        });
    }

    private static void ConfigureRecording(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Recording>(entity =>
        {
            entity.ToTable("recordings", t =>
            {
                t.HasCheckConstraint(
                    "chk_recordings_status",
                    "status IN ('pending_upload', 'pending_moderation', 'pending_review', 'approved', 'rejected')");

                t.HasCheckConstraint(
                    "chk_recordings_duration",
                    "duration_sec > 0 AND duration_sec <= 300");

                t.HasCheckConstraint(
                    "chk_recordings_audio_format",
                    "audio_format IN ('aac', 'm4a', 'mp3')");

                t.HasCheckConstraint(
                    "chk_recordings_category",
                    "category IS NULL OR category IN ('history', 'nature', 'architecture', 'culture', 'personal', 'food', 'music', 'art', 'politics', 'science', 'other')");
            });

            entity.HasKey(e => e.Id);

            entity.Property(e => e.Id)
                .HasColumnName("id")
                .HasDefaultValueSql("gen_random_uuid()");

            entity.Property(e => e.UserId)
                .HasColumnName("user_id")
                .IsRequired();

            entity.Property(e => e.Subject)
                .HasColumnName("subject")
                .HasColumnType("varchar(200)")
                .IsRequired();

            entity.Property(e => e.Description)
                .HasColumnName("description")
                .HasColumnType("text");

            entity.Property(e => e.Location)
                .HasColumnName("location")
                .HasColumnType("geography (point, 4326)")
                .IsRequired();

            entity.Property(e => e.LocationName)
                .HasColumnName("location_name")
                .HasColumnType("varchar(300)");

            entity.Property(e => e.City)
                .HasColumnName("city")
                .HasColumnType("varchar(100)");

            entity.Property(e => e.Region)
                .HasColumnName("region")
                .HasColumnType("varchar(100)");

            entity.Property(e => e.Country)
                .HasColumnName("country")
                .HasColumnType("varchar(100)");

            entity.Property(e => e.AudioBlobKey)
                .HasColumnName("audio_blob_key")
                .HasColumnType("text")
                .IsRequired();

            entity.Property(e => e.AudioFormat)
                .HasColumnName("audio_format")
                .HasColumnType("varchar(10)")
                .HasDefaultValue("aac")
                .IsRequired();

            entity.Property(e => e.DurationSec)
                .HasColumnName("duration_sec")
                .IsRequired();

            entity.Property(e => e.FileSizeBytes)
                .HasColumnName("file_size_bytes");

            entity.Property(e => e.Status)
                .HasColumnName("status")
                .HasColumnType("varchar(30)")
                .HasDefaultValue("pending_moderation")
                .IsRequired();

            entity.Property(e => e.Transcript)
                .HasColumnName("transcript")
                .HasColumnType("text");

            entity.Property(e => e.ModerationScores)
                .HasColumnName("moderation_scores")
                .HasColumnType("jsonb");

            entity.Property(e => e.Category)
                .HasColumnName("category")
                .HasColumnType("varchar(50)");

            entity.Property(e => e.PlayCount)
                .HasColumnName("play_count")
                .HasDefaultValue(0)
                .IsRequired();

            entity.Property(e => e.LikeCount)
                .HasColumnName("like_count")
                .HasDefaultValue(0)
                .IsRequired();

            entity.Property(e => e.CreatedAt)
                .HasColumnName("created_at")
                .HasDefaultValueSql("now()")
                .IsRequired();

            entity.Property(e => e.UpdatedAt)
                .HasColumnName("updated_at")
                .HasDefaultValueSql("now()")
                .IsRequired();

            entity.Property(e => e.DeletedAt)
                .HasColumnName("deleted_at");

            // Relationships
            entity.HasOne(e => e.User)
                .WithMany(u => u.Recordings)
                .HasForeignKey(e => e.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            // GiST spatial index
            entity.HasIndex(e => e.Location)
                .HasMethod("gist")
                .HasDatabaseName("idx_recordings_location");

            // Partial index: approved recordings
            entity.HasIndex(e => e.Status)
                .HasFilter("status = 'approved' AND deleted_at IS NULL")
                .HasDatabaseName("idx_recordings_status_approved");

            // Composite index: user's recordings
            entity.HasIndex(e => new { e.UserId, e.CreatedAt })
                .IsDescending(false, true)
                .HasFilter("deleted_at IS NULL")
                .HasDatabaseName("idx_recordings_user_id");

            // Partial index: pending review
            entity.HasIndex(e => e.CreatedAt)
                .HasFilter("status = 'pending_review' AND deleted_at IS NULL")
                .HasDatabaseName("idx_recordings_pending_review");
        });
    }

    private static void ConfigureModerationRecord(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<ModerationRecord>(entity =>
        {
            entity.ToTable("moderation_records", t =>
            {
                t.HasCheckConstraint(
                    "chk_moderation_action",
                    "action IN ('auto_approve', 'auto_reject', 'escalate_to_review', 'manual_approve', 'manual_reject')");

                t.HasCheckConstraint(
                    "chk_moderation_actor_type",
                    "actor_type IN ('system', 'moderator', 'admin')");
            });

            entity.HasKey(e => e.Id);

            entity.Property(e => e.Id)
                .HasColumnName("id")
                .HasDefaultValueSql("gen_random_uuid()");

            entity.Property(e => e.RecordingId)
                .HasColumnName("recording_id")
                .IsRequired();

            entity.Property(e => e.Action)
                .HasColumnName("action")
                .HasColumnType("varchar(30)")
                .IsRequired();

            entity.Property(e => e.ActorType)
                .HasColumnName("actor_type")
                .HasColumnType("varchar(20)")
                .IsRequired();

            entity.Property(e => e.ActorId)
                .HasColumnName("actor_id")
                .HasColumnType("text");

            entity.Property(e => e.FromStatus)
                .HasColumnName("from_status")
                .HasColumnType("varchar(30)")
                .IsRequired();

            entity.Property(e => e.ToStatus)
                .HasColumnName("to_status")
                .HasColumnType("varchar(30)")
                .IsRequired();

            entity.Property(e => e.Scores)
                .HasColumnName("scores")
                .HasColumnType("jsonb");

            entity.Property(e => e.Reason)
                .HasColumnName("reason")
                .HasColumnType("text");

            entity.Property(e => e.CreatedAt)
                .HasColumnName("created_at")
                .HasDefaultValueSql("now()")
                .IsRequired();

            // Relationships
            entity.HasOne(e => e.Recording)
                .WithMany(r => r.ModerationRecords)
                .HasForeignKey(e => e.RecordingId)
                .OnDelete(DeleteBehavior.Cascade);

            // Composite index: recording + created_at
            entity.HasIndex(e => new { e.RecordingId, e.CreatedAt })
                .HasDatabaseName("idx_moderation_records_recording_id");
        });
    }

    private static void ConfigurePlay(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Play>(entity =>
        {
            entity.ToTable("plays");

            entity.HasKey(e => e.Id);

            entity.Property(e => e.Id)
                .HasColumnName("id")
                .HasDefaultValueSql("gen_random_uuid()");

            entity.Property(e => e.RecordingId)
                .HasColumnName("recording_id")
                .IsRequired();

            entity.Property(e => e.UserId)
                .HasColumnName("user_id")
                .IsRequired();

            entity.Property(e => e.DurationSec)
                .HasColumnName("duration_sec")
                .HasDefaultValue(0)
                .IsRequired();

            entity.Property(e => e.Completed)
                .HasColumnName("completed")
                .HasDefaultValue(false)
                .IsRequired();

            entity.Property(e => e.CreatedAt)
                .HasColumnName("created_at")
                .HasDefaultValueSql("now()")
                .IsRequired();

            // Relationships
            entity.HasOne(e => e.Recording)
                .WithMany(r => r.Plays)
                .HasForeignKey(e => e.RecordingId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(e => e.User)
                .WithMany(u => u.Plays)
                .HasForeignKey(e => e.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            // Indexes
            entity.HasIndex(e => new { e.UserId, e.CreatedAt })
                .IsDescending(false, true)
                .HasDatabaseName("idx_plays_user_id");

            entity.HasIndex(e => e.RecordingId)
                .HasDatabaseName("idx_plays_recording_id");
        });
    }

    private static void ConfigureLike(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Like>(entity =>
        {
            entity.ToTable("likes");

            entity.HasKey(e => e.Id);

            entity.Property(e => e.Id)
                .HasColumnName("id")
                .HasDefaultValueSql("gen_random_uuid()");

            entity.Property(e => e.RecordingId)
                .HasColumnName("recording_id")
                .IsRequired();

            entity.Property(e => e.UserId)
                .HasColumnName("user_id")
                .IsRequired();

            entity.Property(e => e.CreatedAt)
                .HasColumnName("created_at")
                .HasDefaultValueSql("now()")
                .IsRequired();

            // Relationships
            entity.HasOne(e => e.Recording)
                .WithMany(r => r.Likes)
                .HasForeignKey(e => e.RecordingId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(e => e.User)
                .WithMany(u => u.Likes)
                .HasForeignKey(e => e.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            // Unique constraint
            entity.HasIndex(e => new { e.UserId, e.RecordingId })
                .IsUnique()
                .HasDatabaseName("uq_likes_user_recording");
        });
    }

    private static void ConfigureReport(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Report>(entity =>
        {
            entity.ToTable("reports", t =>
            {
                t.HasCheckConstraint(
                    "chk_reports_reason_code",
                    "reason_code IN ('hate_speech', 'harassment', 'violence', 'sexual_content', 'spam', 'misinformation', 'other')");

                t.HasCheckConstraint(
                    "chk_reports_status",
                    "status IN ('submitted', 'reviewing', 'resolved_removed', 'resolved_dismissed')");
            });

            entity.HasKey(e => e.Id);

            entity.Property(e => e.Id)
                .HasColumnName("id")
                .HasDefaultValueSql("gen_random_uuid()");

            entity.Property(e => e.RecordingId)
                .HasColumnName("recording_id")
                .IsRequired();

            entity.Property(e => e.UserId)
                .HasColumnName("user_id")
                .IsRequired();

            entity.Property(e => e.ReasonCode)
                .HasColumnName("reason_code")
                .HasColumnType("varchar(30)")
                .IsRequired();

            entity.Property(e => e.Description)
                .HasColumnName("description")
                .HasColumnType("text");

            entity.Property(e => e.Status)
                .HasColumnName("status")
                .HasColumnType("varchar(20)")
                .HasDefaultValue("submitted")
                .IsRequired();

            entity.Property(e => e.ResolvedBy)
                .HasColumnName("resolved_by");

            entity.Property(e => e.CreatedAt)
                .HasColumnName("created_at")
                .HasDefaultValueSql("now()")
                .IsRequired();

            entity.Property(e => e.ResolvedAt)
                .HasColumnName("resolved_at");

            // Relationships
            entity.HasOne(e => e.Recording)
                .WithMany(r => r.Reports)
                .HasForeignKey(e => e.RecordingId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(e => e.User)
                .WithMany(u => u.Reports)
                .HasForeignKey(e => e.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(e => e.ResolvedByUser)
                .WithMany()
                .HasForeignKey(e => e.ResolvedBy)
                .OnDelete(DeleteBehavior.SetNull);

            // Partial index: open/reviewing reports
            entity.HasIndex(e => e.CreatedAt)
                .HasFilter("status IN ('open', 'reviewing')")
                .HasDatabaseName("idx_reports_status_open");
        });
    }

    private static void ConfigureTag(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Tag>(entity =>
        {
            entity.ToTable("tags", t =>
            {
                t.HasCheckConstraint(
                    "chk_tags_name_lowercase",
                    "name = lower(name)");
            });

            entity.HasKey(e => e.Id);

            entity.Property(e => e.Id)
                .HasColumnName("id")
                .UseIdentityAlwaysColumn();

            entity.Property(e => e.Name)
                .HasColumnName("name")
                .HasColumnType("varchar(50)")
                .IsRequired();

            entity.Property(e => e.CreatedAt)
                .HasColumnName("created_at")
                .HasDefaultValueSql("now()")
                .IsRequired();

            // Unique constraint on name
            entity.HasIndex(e => e.Name)
                .IsUnique()
                .HasDatabaseName("uq_tags_name");
        });
    }

    private static void ConfigureRecordingTag(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<RecordingTag>(entity =>
        {
            entity.ToTable("recording_tags");

            entity.HasKey(e => new { e.RecordingId, e.TagId });

            entity.Property(e => e.RecordingId)
                .HasColumnName("recording_id");

            entity.Property(e => e.TagId)
                .HasColumnName("tag_id");

            // Relationships
            entity.HasOne(e => e.Recording)
                .WithMany(r => r.RecordingTags)
                .HasForeignKey(e => e.RecordingId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(e => e.Tag)
                .WithMany(t => t.RecordingTags)
                .HasForeignKey(e => e.TagId)
                .OnDelete(DeleteBehavior.Cascade);

            // Index on tag_id for reverse lookups
            entity.HasIndex(e => e.TagId)
                .HasDatabaseName("idx_recording_tags_tag_id");
        });
    }
}
