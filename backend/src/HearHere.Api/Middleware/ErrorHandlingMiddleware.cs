using System.Text.Json;
using FluentValidation;
using HearHere.Shared.Exceptions;
using HearHere.Shared.Models.Responses;

namespace HearHere.Api.Middleware;

public class ErrorHandlingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<ErrorHandlingMiddleware> _logger;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };

    public ErrorHandlingMiddleware(RequestDelegate next, ILogger<ErrorHandlingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context);
        }
        catch (Exception ex)
        {
            await HandleExceptionAsync(context, ex);
        }
    }

    private async Task HandleExceptionAsync(HttpContext context, Exception exception)
    {
        var (statusCode, errorResponse) = exception switch
        {
            NotFoundException ex => (StatusCodes.Status404NotFound, new ErrorResponse
            {
                Error = new ErrorDetail { Code = ex.ErrorCode, Message = ex.Message }
            }),

            ForbiddenException ex => (StatusCodes.Status403Forbidden, new ErrorResponse
            {
                Error = new ErrorDetail { Code = ex.ErrorCode, Message = ex.Message }
            }),

            ConflictException ex => (StatusCodes.Status409Conflict, new ErrorResponse
            {
                Error = new ErrorDetail { Code = ex.ErrorCode, Message = ex.Message }
            }),

            ValidationException ex => (StatusCodes.Status400BadRequest, new ErrorResponse
            {
                Error = new ErrorDetail
                {
                    Code = "VALIDATION_ERROR",
                    Message = "Request validation failed.",
                    Details = new
                    {
                        fields = ex.Errors.Select(e => new
                        {
                            field = e.PropertyName,
                            message = e.ErrorMessage
                        })
                    }
                }
            }),

            UnauthorizedAccessException => (StatusCodes.Status401Unauthorized, new ErrorResponse
            {
                Error = new ErrorDetail { Code = "UNAUTHORIZED", Message = "Authentication required." }
            }),

            _ => (StatusCodes.Status500InternalServerError, new ErrorResponse
            {
                Error = new ErrorDetail { Code = "INTERNAL_ERROR", Message = "An unexpected error occurred." }
            })
        };

        if (statusCode == StatusCodes.Status500InternalServerError)
        {
            _logger.LogError(exception, "Unhandled exception");
        }

        context.Response.StatusCode = statusCode;
        context.Response.ContentType = "application/json";
        await context.Response.WriteAsync(JsonSerializer.Serialize(errorResponse, JsonOptions));
    }
}
