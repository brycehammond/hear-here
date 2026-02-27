using System.Text;
using System.Text.Json;
using FluentValidation;
using HearHere.Api.Validators;
using HearHere.Shared.Data;
using HearHere.Shared.Models.Responses;
using Microsoft.EntityFrameworkCore;

namespace HearHere.Api.Endpoints;

public static class DiscoveryEndpoints
{
    public static RouteGroupBuilder MapDiscoveryEndpoints(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/v1/recordings").RequireAuthorization();

        group.MapGet("/nearby", Nearby);

        return group;
    }

    private static async Task<IResult> Nearby(
        double lat,
        double lng,
        HearHereDbContext db,
        IValidator<NearbyQuery> validator,
        int radius = 500,
        int limit = 20,
        string? cursor = null)
    {
        var query = new NearbyQuery
        {
            Lat = lat,
            Lng = lng,
            Radius = radius,
            Limit = limit,
            Cursor = cursor
        };

        await validator.ValidateAndThrowAsync(query);

        limit = Math.Clamp(limit, 1, 50);
        var fetchLimit = limit + 1;

        // Build cursor filter clause
        double? cursorDistance = null;
        Guid? cursorId = null;
        if (!string.IsNullOrEmpty(cursor))
        {
            var cursorData = DecodeCursor(cursor);
            if (cursorData is not null)
            {
                cursorDistance = cursorData.Value.DistanceM;
                cursorId = cursorData.Value.Id;
            }
        }

        // Use raw SQL for PostGIS ST_DWithin query
        List<NearbyRecordingResponse> results;
        if (cursorDistance.HasValue && cursorId.HasValue)
        {
            results = await db.Database
                .SqlQuery<NearbyRecordingRow>($"""
                    SELECT r.id, r.user_id, u.display_name, r.subject, r.description,
                           ST_Y(r.location::geometry) AS latitude,
                           ST_X(r.location::geometry) AS longitude,
                           r.duration_sec, r.status, r.created_at,
                           ST_Distance(r.location, ST_MakePoint({lng}, {lat})::geography) AS distance_m
                    FROM recordings r
                    JOIN users u ON r.user_id = u.id
                    WHERE r.status = 'approved'
                      AND r.deleted_at IS NULL
                      AND ST_DWithin(r.location, ST_MakePoint({lng}, {lat})::geography, {radius})
                      AND (ST_Distance(r.location, ST_MakePoint({lng}, {lat})::geography) > {cursorDistance.Value}
                           OR (ST_Distance(r.location, ST_MakePoint({lng}, {lat})::geography) = {cursorDistance.Value}
                               AND r.id > {cursorId.Value}))
                    ORDER BY distance_m ASC, r.id ASC
                    LIMIT {fetchLimit}
                    """)
                .AsNoTracking()
                .Select(r => new NearbyRecordingResponse
                {
                    Id = r.Id,
                    UserId = r.UserId.ToString(),
                    DisplayName = r.DisplayName,
                    Subject = r.Subject,
                    Description = r.Description,
                    Latitude = r.Latitude,
                    Longitude = r.Longitude,
                    DurationSec = r.DurationSec,
                    Status = r.Status,
                    DistanceM = r.DistanceM,
                    CreatedAt = r.CreatedAt
                })
                .ToListAsync();
        }
        else
        {
            results = await db.Database
                .SqlQuery<NearbyRecordingRow>($"""
                    SELECT r.id, r.user_id, u.display_name, r.subject, r.description,
                           ST_Y(r.location::geometry) AS latitude,
                           ST_X(r.location::geometry) AS longitude,
                           r.duration_sec, r.status, r.created_at,
                           ST_Distance(r.location, ST_MakePoint({lng}, {lat})::geography) AS distance_m
                    FROM recordings r
                    JOIN users u ON r.user_id = u.id
                    WHERE r.status = 'approved'
                      AND r.deleted_at IS NULL
                      AND ST_DWithin(r.location, ST_MakePoint({lng}, {lat})::geography, {radius})
                    ORDER BY distance_m ASC, r.id ASC
                    LIMIT {fetchLimit}
                    """)
                .AsNoTracking()
                .Select(r => new NearbyRecordingResponse
                {
                    Id = r.Id,
                    UserId = r.UserId.ToString(),
                    DisplayName = r.DisplayName,
                    Subject = r.Subject,
                    Description = r.Description,
                    Latitude = r.Latitude,
                    Longitude = r.Longitude,
                    DurationSec = r.DurationSec,
                    Status = r.Status,
                    DistanceM = r.DistanceM,
                    CreatedAt = r.CreatedAt
                })
                .ToListAsync();
        }

        string? nextCursor = null;
        if (results.Count > limit)
        {
            results.RemoveAt(results.Count - 1);
            var last = results[^1];
            nextCursor = EncodeCursor(last.DistanceM, last.Id);
        }

        return Results.Ok(new PaginatedResponse<NearbyRecordingResponse>
        {
            Items = results,
            NextCursor = nextCursor
        });
    }

    private static string EncodeCursor(double distanceM, Guid id)
    {
        var json = JsonSerializer.Serialize(new { distance_m = distanceM, id });
        return Convert.ToBase64String(Encoding.UTF8.GetBytes(json));
    }

    private static (double DistanceM, Guid Id)? DecodeCursor(string cursor)
    {
        try
        {
            var json = Encoding.UTF8.GetString(Convert.FromBase64String(cursor));
            var doc = JsonDocument.Parse(json);
            var distanceM = doc.RootElement.GetProperty("distance_m").GetDouble();
            var id = doc.RootElement.GetProperty("id").GetGuid();
            return (distanceM, id);
        }
        catch
        {
            return null;
        }
    }

    // Internal row type for raw SQL mapping
    private class NearbyRecordingRow
    {
        public Guid Id { get; init; }
        public Guid UserId { get; init; }
        public string DisplayName { get; init; } = string.Empty;
        public string Subject { get; init; } = string.Empty;
        public string? Description { get; init; }
        public double Latitude { get; init; }
        public double Longitude { get; init; }
        public int DurationSec { get; init; }
        public string Status { get; init; } = string.Empty;
        public double DistanceM { get; init; }
        public DateTimeOffset CreatedAt { get; init; }
    }
}
