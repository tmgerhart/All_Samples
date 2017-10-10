require 'rest-client'
require 'json'
require 'csv'


#These are the arguments we are expecting to get
@token = ARGV[0]
@csv_file = ARGV[1]


#Variables we'll need later
@base_url = 'https://api.kennasecurity.com/asset_groups/'
@fixes_url = 'https://api.kennasecurity.com/fixes/'
@headers = {'content-type' => 'application/json', 'X-Risk-Token' => @token }

csv_headers = 
      [
        "Fix Title",
        "Risk Meter Name",
        "Group Number",
        "Fix Number",
        "Current Risk Score",
        "Risk Score Reduction Amount",
        "CVEs",
        "Scanner IDs",
        "Asset IDs",
        "IP Addresses",
        "Diagnosis",
        "Solution",
        "Fix Published Date",
        "ID"
      ]

num_lines = CSV.read(@csv_file).length
puts "Found #{num_lines} lines."

## Iterate through CSV
CSV.foreach(@csv_file, :headers => true){|row|

  current_line = $.
  risk_meter_id = nil

  risk_meter_id = row[0]

  report_url = "#{@base_url}#{risk_meter_id}/top_fixes"

  puts report_url
    
    begin
    query_return = RestClient::Request.execute(
      method: :get,
      url: report_url,
      headers: @headers
    ) 

    json_data = JSON.parse(query_return.body)["asset_group"]

    risk_meter_name = json_data.fetch("name").gsub('/','-').gsub(' ','_')
    current_risk_score = json_data.fetch("risk_meter_score")

    filename = "#{risk_meter_name.gsub(/\s+/,"_")}.csv"

    CSV.open(filename , 'w') do |csv|
    csv << csv_headers

      top_fix_data = json_data["top_fixes"]

      top_fix_data.each do |fix_group|
        fix_group_number = fix_group.fetch("fix_group_number")
        fix_risk_reduction = fix_group.fetch("risk_score_reduction")
        fixes_data = fix_group["fixes"]
        fix_index = 0
        fixes_data.each do |fix|
          fix_title = fix.fetch("title")
          fix_id = fix.fetch("id")
          fix_index += 1
          fix_cves = fix.fetch("cves")
          fix_diagnosis = fix.fetch("diagnosis")
          fix_solution = fix.fetch("solution")
          fix_url = "#{@fixes_url}/#{fix_id}"
          query_return = RestClient::Request.execute(
            method: :get,
            url: fix_url,
            headers: @headers
          ) 
          fix_data = JSON.parse(query_return.body)["fix"]
          patch_publication_date = fix_data.fetch("patch_publication_date")
          scanner_ids = fix_data.fetch("scanner_ids")
          ip_addresses = []
          asset_ids = []
          fix_assets = fix["assets"]
          fix_assets.each do |asset|
            asset_ids << asset.fetch("id")
            ip_addresses << asset.fetch("ip_address")

          end


          csv << [fix_title,
                  risk_meter_name,
                  fix_group_number,
                  fix_index,
                  current_risk_score,
                  fix_risk_reduction,
                  fix_cves.join(" "),
                  scanner_ids.join(" "),
                  asset_ids.join(" "),
                  ip_addresses.join(" "),
                  fix_diagnosis,
                  fix_solution,
                  patch_publication_date,
                  fix_id]

        end
      end
   end

  # Let's put our code in safe area
    rescue Exception => e  
       print "Exception occured: " + e.backtrace.inspect  
    end 

}
