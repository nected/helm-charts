# Minimal JSON reader for flat objects of string values.
#
# There is no jq or python3 in the job image, and a credential parser that
# silently corrupts a value is worse than one that refuses it - so unsupported
# input is always a hard error rather than a best guess.
#
# Modes:
#   -v mode=files -v dir=D   write every string value to D/<KEY>, print the count.
#                            A non-string value is fatal: a quoted port or
#                            boolean in a credential blob is a mistake worth
#                            surfacing, not dropping.
#   -v mode=one -v key=K     print the decoded value of K. Other keys are
#                            ignored whatever their type, because provider API
#                            responses mix strings with numbers and nulls.

function fail(msg) { print "ERROR: " msg > "/dev/stderr"; bad = 1; exit 1 }

function hex4(h,   i, c, n, d) {
  n = 0
  for (i = 1; i <= 4; i++) {
    c = tolower(substr(h, i, 1))
    d = index("0123456789abcdef", c) - 1
    if (d < 0) return -1
    n = n * 16 + d
  }
  return n
}

# Decodes the JSON string starting at s[i] (the opening quote). Result in the
# global "val"; the offset just past the closing quote in the global "next_i".
function read_string(s, i,    out, c, esc, n) {
  if (substr(s, i, 1) != "\"") fail("expected a string at offset " i)
  i++
  out = ""
  while (i <= length(s)) {
    c = substr(s, i, 1)
    if (c == "\\") {
      esc = substr(s, i + 1, 1)
      if      (esc == "n")  out = out "\n"
      else if (esc == "t")  out = out "\t"
      else if (esc == "r")  out = out "\r"
      else if (esc == "b")  out = out sprintf("%c", 8)
      else if (esc == "f")  out = out sprintf("%c", 12)
      else if (esc == "/")  out = out "/"
      else if (esc == "\\") out = out "\\"
      else if (esc == "\"") out = out "\""
      else if (esc == "u") {
        n = hex4(substr(s, i + 2, 4))
        # Emitting a non-ASCII code point would need a UTF-8 encoder. Raw
        # UTF-8 bytes in the input pass through untouched, so the only thing
        # refused here is the \u form.
        if (n > 0 && n < 128) { out = out sprintf("%c", n); i += 4 }
        else fail("\\u escape outside ASCII is not supported; store the value as plain UTF-8 or base64")
      }
      else fail("unknown escape \\" esc)
      i += 2
      continue
    }
    if (c == "\"") { val = out; next_i = i + 1; return }
    out = out c
    i++
  }
  fail("unterminated string")
}

# Skips one value of any type at s[i]; leaves the offset past it in next_i.
function skip_value(s, i,    c, depth, instr) {
  c = substr(s, i, 1)
  if (c == "\"") { read_string(s, i); return }
  if (c == "{" || c == "[") {
    depth = 0; instr = 0
    while (i <= length(s)) {
      c = substr(s, i, 1)
      if (instr) {
        if (c == "\\") i++
        else if (c == "\"") instr = 0
      }
      else if (c == "\"") instr = 1
      else if (c == "{" || c == "[") depth++
      else if (c == "}" || c == "]") { depth--; if (depth == 0) { next_i = i + 1; return } }
      i++
    }
    fail("unterminated object or array")
  }
  # number, true, false, null
  while (i <= length(s) && substr(s, i, 1) !~ /[,}]/) i++
  next_i = i
}

{ body = body $0 "\n" }

END {
  if (bad) exit 1
  gsub(/^[ \t\n\r]+|[ \t\n\r]+$/, "", body)
  if (substr(body, 1, 1) != "{" || substr(body, length(body), 1) != "}")
    fail("expected a JSON object")

  i = 2
  count = 0
  while (i <= length(body)) {
    while (i <= length(body) && substr(body, i, 1) ~ /[ \t\n\r,]/) i++
    if (i > length(body) || substr(body, i, 1) == "}") break

    read_string(body, i); if (bad) exit 1
    k = val; i = next_i

    while (i <= length(body) && substr(body, i, 1) ~ /[ \t\n\r]/) i++
    if (substr(body, i, 1) != ":") fail("expected : after key \"" k "\"")
    i++
    while (i <= length(body) && substr(body, i, 1) ~ /[ \t\n\r]/) i++

    if (mode == "one") {
      if (k == key) {
        if (substr(body, i, 1) != "\"") fail("value of \"" k "\" is not a string")
        read_string(body, i); if (bad) exit 1
        printf "%s", val
        found = 1
        exit 0
      }
      skip_value(body, i); if (bad) exit 1
      i = next_i
      continue
    }

    if (substr(body, i, 1) != "\"")
      fail("value of \"" k "\" is not a string; store every value quoted")
    read_string(body, i); if (bad) exit 1
    v = val; i = next_i

    # Keys become filenames, so anything outside the env-var charset is
    # refused rather than used to build a path from untrusted input.
    if (k !~ /^[A-Za-z_][A-Za-z0-9_.-]*$/) {
      print "WARNING: skipping key with unusable name: " k > "/dev/stderr"
      continue
    }
    printf "%s", v > (dir "/" k)
    close(dir "/" k)
    count++
  }

  if (bad) exit 1
  if (mode == "one") { if (!found) exit 2; exit 0 }
  print count
}
