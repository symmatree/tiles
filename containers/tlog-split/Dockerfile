# One tlog per flight, off a mavproxy fan-out. See split_tlog.py for why this exists rather
# than rotating mavproxy's own log (coordinator#192).
FROM python:3.13-slim@sha256:4c2cf9917bd1cbacc5e9b07320025bdb7cdf2df7b0ceaccb55e9dd7e30987419

# pymavlink pinned: this parses a wire format and writes a file other tools read. A silent
# dialect change is the kind of thing that shows up as a corrupt flight record months later.
ARG PYMAVLINK_VERSION=2.4.49
RUN pip install --no-cache-dir "pymavlink==${PYMAVLINK_VERSION}"

COPY split_tlog.py /app/split_tlog.py
USER 1000
ENTRYPOINT ["python3", "-u", "/app/split_tlog.py"]
