require "sinatra"
require "sinatra/reloader"
require "http"
require "erb"
require "sinatra/cookies"
require "openai"
require "kramdown"

get("/") do
  "Welcome to Omnicalc 3"
end


get("/umbrella") do
  erb(:umbrella_form)
end

post("/process_umbrella") do
  @user_loc = params.fetch("user_location")

  url_encoded_loc = ERB::Util.url_encode(@user_loc)

  gmaps_url = "https://maps.googleapis.com/maps/api/geocode/json?address=#{url_encoded_loc}&key=#{ENV.fetch("GMAPS_API_KEY")}"

  gmaps_raw_response = HTTP.get(gmaps_url).to_s

  gmaps_parsed_response = JSON.parse(gmaps_raw_response)

  loc_hash = gmaps_parsed_response.dig("results", 0, "geometry", "location")

  @latitude = loc_hash.fetch("lat")
  @longitude = loc_hash.fetch("lng")

  pirate_weather_url = "https://api.pirateweather.net/forecast/#{ENV.fetch("PIRATE_API_KEY"}/#{@latitude},#{@longitude}"

  pirate_raw_response = HTTP.get(pirate_weather_url).to_s

  pirate_parsed_response = JSON.parse(pirate_raw_response)

  currently_hash = pirate_parsed_response.fetch("currently")
  
  @current_temp = currently_hash.fetch("temperature")

  @current_summary = currently_hash.fetch("summary")

  hourly_hash = pirate_parsed_response.fetch("hourly")

  hourly_data_array = hourly_hash.fetch("data")

  next_twelve_hours = hourly_data_array[1..12]

  precip_prob_threshold = 0.10

  any_precipitation = false

  next_twelve_hours.each do |hour_hash|
    precip_prob = hour_hash.fetch("precipProbability")

    if precip_prob > precip_prob_threshold
      any_precipitation = true

      precip_time = Time.at(hour_hash.fetch("time"))

      seconds_from_now = precip_time - Time.now

      hours_from_now = seconds_from_now / 60 / 60

      puts "In #{hours_from_now.round} hours, there is a #{(precip_prob * 100).round}% chance of precipitation."
    end
  end

  if any_precipitation == true
    @umbrella = "You might want to take an umbrella!"
  else
    @umbrella = "You probably won't need an umbrella."
  end

  erb(:umbrella_results)
end

get("/message") do
  erb(:gpt_single_message)
end

post("/process_single_message") do
  @user_message = params.fetch("the_message")

  openai_client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))

  api_response = openai_client.chat(
    parameters: {
      model: "gpt-4",
      messages: [
        { :role => "system", :content => "You are a helpful assistant that talks like Shakespeare." },
        { :role => "user", :content => @user_message }
      ],
      temperature: 0.7,
    }
  )

  choices_array = api_response.fetch("choices")
  first_choice = choices_array.at(0)
  message_hash = first_choice.fetch("message")

  @ai_message = message_hash.fetch("content")

  erb(:gpt_single_message_results)
end

get("/chat") do
  old_chat_history_string = cookies["chat_history"]

  if old_chat_history_string == nil
    @chat_history_array = []
  else
    @chat_history_array = JSON.parse(old_chat_history_string)
  end

  erb(:gpt_chat)
end

post("/add_message_to_chat") do
  new_message = params.fetch("user_message")

  old_chat_history_string = cookies["chat_history"]

  if old_chat_history_string == nil
    chat_history_array = []
  else
    chat_history_array = JSON.parse(old_chat_history_string)
  end

  chat_history_array.push(
    { :role => "user", :content => new_message }
  )
  
  openai_client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))

  response = openai_client.chat(
    parameters: {
        model: "gpt-4",
        messages: chat_history_array,
        temperature: 0.7,
    }
  )

  choices_array = response.fetch("choices")
  first_choice = choices_array.at(0)
  message_hash = first_choice.fetch("message")
  new_ai_reply = message_hash.fetch("content")

  chat_history_array.push(
    { :role => "assistant", :content => new_ai_reply}
  )

  new_chat_history_string = JSON.generate(chat_history_array)

  cookies["chat_history"] = new_chat_history_string

  redirect("/chat")
end

post("/clear_chat") do
  cookies.delete("chat_history")

  redirect("/chat")
end
