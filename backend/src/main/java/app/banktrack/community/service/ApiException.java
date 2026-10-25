package app.banktrack.community.service;

import org.springframework.http.HttpStatus;

/** A request the community refuses, with the reason the app shows. */
public class ApiException extends RuntimeException {
    private final HttpStatus status;

    public ApiException(HttpStatus status, String message) {
        super(message);
        this.status = status;
    }

    public HttpStatus getStatus() { return status; }

    public static ApiException notFound(String message) { return new ApiException(HttpStatus.NOT_FOUND, message); }

    public static ApiException conflict(String message) { return new ApiException(HttpStatus.CONFLICT, message); }

    public static ApiException refused(String message) { return new ApiException(HttpStatus.UNPROCESSABLE_CONTENT, message); }
}
