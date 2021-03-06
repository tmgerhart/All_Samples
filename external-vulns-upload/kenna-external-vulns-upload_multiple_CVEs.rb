# kenna-external-vulns
require 'rest-client'
require 'json'
require 'csv'

@token = ARGV[0]
@data_file = ARGV[1]
@custom_field_meta = ARGV[2] #csv of column names in data and what custom field to put them in 
@primary_locator = ARGV[3] #hostname or ip_address or url or application
@locator_column = ARGV[4] #column in csv that has primary locator info (actual ip, hostname or url)
@vuln_type = ARGV[5] # cve or cwe or wasc
@vuln_column = ARGV[6] #column that holds the vuln data
@notes_meta = ARGV[7] #prefix and column names to be included in notes
@hostcase = ARGV[8] #upcase, downcase or nochange
@last_seen_column = ARGV[9]
@first_found_column = ARGV[10]
@due_date_column = ARGV[11]
@status = ARGV[12]
@identifier = ARGV[13]

@vuln_api_url = 'https://api.kennasecurity.com/vulnerabilities'
@search_url = '/search?q='
@headers = {'content-type' => 'application/json', 'X-Risk-Token' => @token, 'accept' => 'application/json'}
@max_retries = 5
@debug = false

# Encoding characters
enc_colon = "%3A"
enc_dblquote = "%22"
enc_space = "%20"

## Query API with query_url
asset_id = nil
key = nil
vuln_id = nil
status = nil
serviceName = nil
@custom_fields  = []
@notes_fields = []

start_time = Time.now
output_filename = "kenna-external-vulns_log-#{start_time.strftime("%Y%m%dT%H%M")}.txt"

def build_ip_url(ipstring)
  puts "building ip url" if @debug
  url = ""
  if ipstring.index('/').nil? then
    subnet = IPAddr.new(ipstring)
    url = "ip:#{@enc_dblquote}#{subnet}#{@enc_dblquote}"
  else 
    subnet = IPAddr.new(ipstring)
    iprange = subnet.to_range()
    beginip = iprange.begin
    endip = iprange.end
    url = "ip:" + "[" + "#{beginip}" + " TO " + "#{endip}" + "]"
  end
  return url
end

def build_hostname_url(hostname)
  puts "building hostname url" if @debug
  if @hostcase == 'upcase'
    hostname.upcase!
  elsif @hostcase == 'downcase'
    hostname.downcase!
  end
  return "hostname:#{@enc_dblquote}#{hostname}*#{@enc_dblquote}"
end

def is_ip?(str)
  !!IPAddr.new(str) rescue false
end

def cleanVulnData(vulnData)
  finalvulns = []
  puts "before #{vulnData}"
  if !vulnData.nil? && @vuln_type == "cve" then
    vulnData = vulnData.gsub(/\(.*?\)/, "") 
    puts "removed paren #{vulnData}"
    vulnData = vulnData.gsub(/\s+/, '')
    temp_vulns = vulnData.split(",")
    temp_vulns.each do |value|
      finalvulns << value.sub(/\ACVE-/, '')[0..8]
    end
  end
  puts "size #{finalvulns.size}"
  return finalvulns
end  

if !@custom_field_meta.empty? then
  CSV.foreach(@custom_field_meta, :headers => true, :encoding => "UTF-8"){|row|

    @custom_fields << Array[row[0],row[1]]

  }
end
if !@notes_meta.empty? then
  CSV.foreach(@notes_meta, :headers => true, :encoding => "UTF-8"){|row|

    @notes_fields << Array[row[0],row[1]]

  }
end

CSV.foreach(@data_file, :headers => true, :encoding => "UTF-8"){|row|

    locator = row["#{@locator_column}"]

    notes = ""
    custom_field_string = ""
    query_url = ""
    temp_uri = ""
    status = row["#{@status}"]
    identifier = row["#{@identifier}"]
    api_query = nil 

    
    if !row["#{@locator_column}"].nil? then
      if @primary_locator == "ip_address" then
        api_query = build_ip_url(row["#{@locator_column}"])
      elsif @primary_locator == "hostname" then
        api_query = build_hostname_url(row["#{@locator_column}"])
      elsif @primary_locator =="url" then
        if !locator.start_with?('http') then
          locator = "http://#{locator}"
        end 
        api_query = "url:#{enc_dblquote}#{locator}#{enc_dblquote}"
      elsif @primary_locator == "application" then
        api_query = "application:#{enc_dblquote}#{locator}#{enc_dblquote}"
      end
    end
    vuln_array = []
    if !@vuln_type.nil? then
      temp_vuln_array = cleanVulnData( row[@vuln_column])
      temp_vuln_array.each do |value|
        if @vuln_type == "vuln_id" then
          vuln_array << "id%5B%5D=#{value}"
        else
          vuln_array << "#{@vuln_type}:#{value}"
        end
      end
    end
    queries = []
    if vuln_array.any? then
      vuln_array.each do |vuln_item|
        if @vuln_type == "vuln_id" then
          query_url = "#{@vuln_api_url}#{@search_url}#{query_url}#{vuln_item}"
        else
          query_url = "#{@vuln_api_url}#{@search_url}#{@urlquerybit}#{vuln_item}"
        end
        query_url = query_url.gsub(/\&$/, '')
        if !api_query.nil? then
          query_url = "#{query_url}+AND+#{api_query}"    
        end
        queries << [query_url,vuln_item]
      end
    else
      query_url = "#{@vuln_api_url}#{@search_url}#{@urlquerybit}"
      query_url = query_url.gsub(/\&$/, '')
      queries << query_url
    end



   

    puts "query url = #{queries[0]}"

    if !@last_seen_column.nil? && !@last_seen_column == "" then 
      last_seen = DateTime.parse(row["#{@last_seen_column}"]).strftime("%FT%TZ")
    else
      last_seen = Time.now.strftime("%FT%TZ")
    end

    @notes_fields.each{|item| 
      row_value = row[item[0]]
      if !row_value.nil? then
        row_value = row_value.gsub(/['<','>','_','\n','\t','\r',':','(',')',''',"{","}"]/,'').chomp
        notes << "#{item[1]}#{row_value}"
      end
    }

    @custom_fields.each{|item| 
      row_value = row[item[0]]
      if !row_value.nil? then
        row_value = row_value.gsub(/['<','>','_','\n','\t','\r',':','(',')',''',"{","}"]/,'').chomp
        custom_field_string << "\"#{item[1]}\":\"#{row_value}\","
      end
    }

    custom_field_string = custom_field_string[0...-1]

    
    queries.each do |query|

      find_vuln_query = query[0]
      vuln_cve = query[1]

      begin
          vuln_id = nil
          begin
            get_response = RestClient::Request.execute(
              method: :get,
              url: find_vuln_query,
              headers: @headers,
            )
            get_response_json = JSON.parse(get_response)["vulnerabilities"]
            get_response_json.each do |item|
              vuln_id = item["id"]
            end
            puts "vuln_id= #{vuln_id}" if @debug
          end
          #vuln_column_data = row[@vuln_column][0..12]
          vuln_create_json_string = "{\"vulnerability\":{\"#{@vuln_type}_id\":\"#{vuln_cve.sub! 'cve:', 'CVE-'}\",\"primary_locator\":\"#{@primary_locator}\","\
              "\"last_seen_time\":\"#{last_seen}\","

          if !@first_found_column.empty? then 
            vuln_create_json_string = "#{vuln_create_json_string}\"found_on\":\"#{DateTime.parse(row[@first_found_column]).strftime('%FT%TZ')}\"," 
          end

          if !@due_date_column.empty? then
            vuln_create_json_string = "#{vuln_create_json_string}\"due_date\":\"#{DateTime.parse(row[@due_date_column]).strftime('%FT%TZ')}\"," 
          end

          if !@identifier.empty? then
            vuln_create_json_string = "#{vuln_create_json_string}\"identifier\":\"#{identifier}\","
          end

             
          vuln_create_json_string = "#{vuln_create_json_string}\"#{@primary_locator}\":\"#{locator}\"}}"

          vuln_create_json = JSON.parse(vuln_create_json_string)

          vuln_update_json_string = "{\"vulnerability\":{"

          if status.nil? || status.empty? then
            vuln_update_json_string = "#{vuln_update_json_string}\"status\":\"open\""
          else
            vuln_update_json_string = "#{vuln_update_json_string}\"status\":\"#{status}\""
          end
          if !@custom_field_meta.empty? then
            vuln_update_json_string = "#{vuln_update_json_string},\"custom_fields\":{#{custom_field_string}}\""
          end
          if !@notes_meta.empty? then
            vuln_update_json_string = "#{vuln_update_json_string},\"notes\":\"#{notes}\""
          end
         vuln_update_json_string = "#{vuln_update_json_string},\"last_seen_time\":\"#{last_seen}\"}}"
         #vuln_update_json_string = "#{vuln_update_json_string}}}"
          
          puts vuln_update_json_string if @debug
          vuln_update_json = JSON.parse(vuln_update_json_string)

          puts vuln_create_json
          puts vuln_update_json if @debug

          begin
            if vuln_id.nil? then
              log_output = File.open(output_filename,'a+')
              log_output << "Kenna Creating Vuln for new asset. #{row[@vuln_column]} AND #{row[@locator_column]}\n"
              log_output.close
              puts "creating new vuln" if @debug
              update_response = RestClient::Request.execute(
                method: :post,
                url: @vuln_api_url,
                headers: @headers,
                payload: vuln_create_json
              )

              update_response_json = JSON.parse(update_response)["vulnerability"]
              if !@some_var.class == Hash then 
                new_json = JSON.parse(update_response_json)
              else
                new_json = update_response_json
              end

              vuln_id = new_json.fetch("id")
          end

            vuln_custom_uri = "#{@vuln_api_url}/#{vuln_id}"
            puts vuln_custom_uri if @debug
            log_output = File.open(output_filename,'a+')
            log_output << "Kenna updating vuln: #{vuln_id} for #{row[@vuln_column]} AND #{row[@locator_column]}\n"
            log_output.close
            puts "updating vuln" if @debug
            update_response = RestClient::Request.execute(
              method: :put,
              url: vuln_custom_uri,
              headers: @headers,
              payload: vuln_update_json
            )
            puts update_response
            if update_response.code == 204 then next end
            
          end


        #end
        rescue RestClient::UnprocessableEntity => e
          log_output = File.open(output_filename,'a+')
          log_output << "UnprocessableEntity: #{e.message}... (time: #{Time.now.to_s}, start time: #{start_time.to_s})\n"
          log_output.close
          puts "UnprocessableEntity: #{e.message}"

        rescue RestClient::BadRequest => e
          log_output = File.open(output_filename,'a+')
          log_output << "BadRequest: #{e.message}... (time: #{Time.now.to_s}, start time: #{start_time.to_s})\n"
          log_output.close
          puts "BadRequest: #{e.message}"
        rescue RestClient::Exception => e
          puts "i hit an exception #{e.message} #{e.backtrace.inspect}"

          @retries ||= 0
          if @retries < @max_retries
            @retries += 1
            sleep(15)
            retry
          else
            log_output = File.open(output_filename,'a+')
            log_output << "General RestClient error #{e.message}... (time: #{Time.now.to_s}, start time: #{start_time.to_s})\n"
            log_output.close
            puts "Exception: #{e.message}"
          end
      end
    end
  }
