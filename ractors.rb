require "json"

# Create a Ractor that processes file checks in a loop.
r = Ractor.new do
  loop do
    puts 1
    sleep 1
    # Receive a message from the sender.
    file_name, expected_content = Ractor.receive

    # Check if the file's content exactly matches the expected content.
    begin
      result = File.read(file_name) == expected_content
    rescue StandardError => e
      # If there's an error (e.g., file doesn't exist), return false.
      result = false
    end

    # Yield the result back to the sender.
    Ractor.yield result
  end
end

r.send(["example.txt", "Hello, Ractor!"])
result = r.take

puts "Does the file content match? #{result}"
