require "json"

# Runs the YAML test suite (its data branch) through build/suite and
# counts the cases that pass: a valid case's events match test.event, and
# an error case ends in an error. Then build/json loads each valid case
# that has an in.json under the Core schema and compares the values.
#
# Last, build/roundtrip writes each valid case's documents back with dump
# and checks that loading them gives the same values.
#
#   script/suite ~/yaml-test-suite-data [ID ...]
#
# With IDs, it prints those cases' expected and actual events.

dir = ARGV.shift or abort "usage: ruby test/suite.rb <yaml-test-suite data> [ID ...]"
show = ARGV
root = File.expand_path("..", __dir__)
cases = Dir["#{dir}/**/in.yaml"].map { |f| File.dirname(f) }.sort
File.write("#{root}/build/paths.txt", cases.map { |c| "#{c}/in.yaml" }.join("\n"))
out = IO.popen(["#{root}/build/suite", "#{root}/build/paths.txt"], &:read)
got = {}
out.split(/^### /).drop(1).each do |chunk|
  path, rest = chunk.split("\n", 2)
  got[File.dirname(path)] = rest.to_s
end

id = ->(c) { c.delete_prefix("#{dir}/") }
tally = Hash.new(0)
failed = []
cases.each do |c|
  actual = got[c] or (failed << [id.(c), "no output"]; next)
  error = actual.lines.grep(/^ERROR /).first
  events = actual.lines.reject { |l| l.start_with?("ERROR ") }.join
  if File.exist?("#{c}/error")
    ok = !error.nil?
    tally[ok ? :error_pass : :error_fail] += 1
    failed << [id.(c), "expected an error"] unless ok
  else
    expected = File.read("#{c}/test.event")
    ok = error.nil? && events == expected
    tally[ok ? :valid_pass : :valid_fail] += 1
    failed << [id.(c), error ? error.strip : "events differ"] unless ok
  end
  if show.include?(id.(c))
    puts "== #{id.(c)}: #{File.read("#{c}/===").strip rescue ''}"
    puts File.read("#{c}/in.yaml").gsub("\t", "<TAB>")
    puts "-- expected"
    puts File.exist?("#{c}/error") ? "(error)" : File.read("#{c}/test.event")
    puts "-- actual"
    puts actual
  end
end
failed.each { |i, why| puts "FAIL #{i}: #{why}" } if show.empty?
valid = tally[:valid_pass] + tally[:valid_fail]
errs = tally[:error_pass] + tally[:error_fail]
puts "valid: #{tally[:valid_pass]}/#{valid}  error: #{tally[:error_pass]}/#{errs}  total: #{tally[:valid_pass] + tally[:error_pass]}/#{valid + errs}"

# The values: in.json holds one JSON text per document, one after another.
def json_stream(text)
  docs = []
  buf = +""
  text.each_line do |line|
    buf << line
    begin
      docs << JSON.parse(buf)
      buf = +""
    rescue JSON::ParserError
    end
  end
  docs
end

out = IO.popen(["#{root}/build/json", "#{root}/build/paths.txt"], &:read)
loaded = {}
out.split(/^### /).drop(1).each do |chunk|
  path, rest = chunk.split("\n", 2)
  loaded[File.dirname(path)] = rest.to_s
end
jpass = 0
jfail = []
cases.each do |c|
  next if File.exist?("#{c}/error") || !File.exist?("#{c}/in.json")
  expected = json_stream(File.read("#{c}/in.json"))
  actual = loaded[c].to_s
  got = actual.start_with?("ERROR") ? actual.strip : actual.lines.map { |l| JSON.parse(l) rescue l.strip }
  if got == expected
    jpass += 1
  else
    jfail << [id.(c), got]
  end
  if show.include?(id.(c))
    puts "-- in.json"
    puts expected.inspect
    puts "-- loaded"
    puts got.inspect
  end
end
jfail.each { |i, g| puts "JSON FAIL #{i}: #{g.inspect[0, 200]}" } if show.empty?
puts "json: #{jpass}/#{jpass + jfail.size}"

# And back: each valid case's documents, written by dump and loaded again.
out = IO.popen(["#{root}/build/roundtrip", "#{root}/build/paths.txt"], &:read)
same = 0
differ = []
out.split(/^### /).drop(1).each do |chunk|
  path, rest = chunk.split("\n", 2)
  c = File.dirname(path)
  next if File.exist?("#{c}/error")
  rest.to_s.scan(/^(same|differs)/).each { |(w)| w == "same" ? same += 1 : differ << id.(c) }
end
differ.uniq.each { |i| puts "ROUNDTRIP FAIL #{i}" } if show.empty?
puts "dump round trip: #{same}/#{same + differ.size} documents"
