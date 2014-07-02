require 'nokogiri'
require 'open-uri'
require "pp"

doc = nil
File.open(ARGV[0]) do |file|
  doc = Nokogiri::HTML::Document.parse(
    file, 
    "http://www.rentfaster.ca/compare.php?printer_friendly=yes&favs=all",
    "UTF-8")
end

def raw_value(property)
  ->(cell,apartment) {
    apartment[property.to_sym] = cell.content
  }
end

def raw_number(property)
  ->(cell,apartment) {
    number = cell.content.to_f
    if number == 0.0
      apartment[property.to_sym] = cell.content
    else
      apartment[property.to_sym] = number
    end
  }
end

def checkbox(property)
  ->(cell,apartment) {
    img = cell.css("img")[0]
    apartment[property.to_sym] = (img[:src] == "/images/checkmark.gif")
  }
end

def allowed(property)
  ->(cell,apartment) {
    apartment[property.to_sym] = case cell.content
    when "Allowed"
      true
    when "Not Allowed"
      false
    when ""
      nil
    else 
      cell.content
    end
  }
end

def distance(property)
  ->(cell,apartment) {
    matched, distance = cell.content.match(/(.+) km/).to_a
    apartment[:distance] ||= {}
    if matched
      apartment[:distance][property] = distance.to_f
    else
      apartment[:distance][property] = nil
    end
  }
end

def skip(description)
  ->(cell,apartment) {
    
  }
end

properties = []

properties << ->(cell,apartment) {
  cell_class = cell.attributes['class'].content
  cell_class_value, id, suffix = *cell_class.match(/compare-listing-(.+)_(.+)/)
  apartment[:id] = id
  apartment[:suffix] = suffix
  
  apartment[:title] = cell.css("b")[0].content
}

properties << ->(cell,apartment){
  img = cell.css("img")[0]
  thumb_path = img["src"]
  apartment[:photos] = {
    thumbnail: "http://www.rentfaster.ca#{thumb_path}"
  }
}

properties << raw_value(:listing_number)
properties << raw_value(:address)
properties << raw_value(:community)
properties << raw_value(:property_type)
properties << raw_number(:rent)
properties << raw_number(:bedrooms)
properties << raw_number(:bathrooms)
properties << skip("utilities included")
properties << checkbox(:heat)
properties << checkbox(:electricity)
properties << checkbox(:water)
properties << checkbox(:cable)
properties << checkbox(:satellite)
properties << checkbox(:internet)
properties << allowed(:under18)
properties << allowed(:pets)
properties << allowed(:dogs)
properties << allowed(:cats)
properties << allowed(:smoking)
properties << ->(cell, apartment) {
  matched, grade, security = cell.content.match(/(.+) - (.+)/).to_a
  apartment[:parking] = {:description => cell.content}
  if matched
    unless grade == "other"
      apartment[:parking][:grade] = grade
      apartment[:parking][:security] = security
    end
  end  
}
properties << skip("how far to...")
properties << distance(:victoria_park)
properties << distance(:_39_ave)
properties << distance(:_45_st)
properties << distance(:_69_st)
properties << distance(:ach)
properties << distance(:acad)
properties << distance(:ambrose)
properties << distance(:anderson)
properties << distance(:banf_trail)
properties << distance(:barlow_max_bell)
properties << distance(:bow_valley_college)
properties << distance(:brentwood)
properties << distance(:bridgeland)
properties << distance(:airport)
properties << distance(:zoo)
properties << distance(:canyon_meadows)
properties << distance(:chinook_mall)
properties << distance(:chinook_station)
properties << distance(:city_hall)
properties << distance(:crossiron_mills)
properties << distance(:crowfoot)
properties << distance(:dalhousie)
properties << distance(:deerfoot_mall)
properties << distance(:devry)
properties << distance(:downtown)
properties << distance(:erlton)
properties << distance(:fish_creek)
properties << distance(:foothills_hospital)
properties << distance(:franklin)
properties << distance(:heritage)
properties << distance(:lions_park)
properties << distance(:market_mall)
properties << distance(:marlborough)
properties << distance(:martindale)
properties << distance(:mcknight)
properties << distance(:mru)
properties << distance(:peter_lougheed)
properties << distance(:rmc)
properties << distance(:rockyview)
properties << distance(:rundle)
properties << distance(:saddletowne)
properties << distance(:sait)
properties << distance(:sait_station)
properties << distance(:shaganappi)
properties << distance(:shawnessy)
properties << distance(:sirocco)
properties << distance(:somerset)
properties << distance(:southcentre)
properties << distance(:southland)
properties << distance(:sunalta)
properties << distance(:sunridge)
properties << distance(:uofc)
properties << distance(:university_station)
properties << distance(:westbrook)
properties << distance(:whitehorn)
properties << distance(:zoo_station)

apartments = []

rows = doc.css("table.tblCompare tr")
property_index = 0
rows.each do |row|
  property = properties[property_index]
  if property

    cells = row.css("td")
    title = row[0]
    apartment_cells = cells[1...-1]
  
    apartment_index = 0
    apartment_cells.each do |cell|
      apartment = (apartments[apartment_index] ||= {})
    
      property.call(cell, apartment)
    
      apartment_index += 1
    end
  end
  
  property_index += 1
end

weights = {
  :total_cost => 0.85,
  :community => 0.25,
  :property_type => 0.25,
  :bedrooms => 0.75,
  :bathrooms => 0.1,
  :under_18 => -0.15,
  :pets => -0.15,
  :smoking => -0.5,
  :parking => 0.5,
  :distance => 0.5
}

extra_costs = {
  :heat => 40,
  :electricity => 90,
  :water => 15,
  :tv => 10,
  :internet => 50,
}

apartments.each do |apartment|
  total_cost = apartment[:rent]
  total_cost += extra_costs[:heat] unless apartment[:heat]
  total_cost += extra_costs[:electricity] unless apartment[:electricity]
  total_cost += extra_costs[:water] unless apartment[:water]
  total_cost += extra_costs[:tv] unless apartment[:cable] || apartment[:satellite]
  total_cost += extra_costs[:internet] unless apartment[:internet]
  apartment[:total_cost] = total_cost
end

rents = apartments.map {|a| a[:total_cost]}.sort
low_rent = rents[rents.size / 3]
puts "Low Rent: #{low_rent}"
high_rent= rents[rents.size / 3 * 2]
puts "High Rent: #{high_rent}"

communities = []
property_types = []

apartments.each do |apartment|
  analysis = apartment[:analysis] ||= {}
  score = 0.0
  if apartment[:total_cost] < low_rent
    analysis[:total_cost] = "Low cost"
    score += 1 * weights[:total_cost]
  elsif apartment[:total_cost] > high_rent
    analysis[:total_cost] = "High cost"
    score += -1 * weights[:total_cost]
  else
    analysis[:total_cost] = "Medium cost"
  end
  
  analysis[:score] = score
  
  case apartment[:community].downcase
  when "downtown"
    score += 1 * weights[:property_type]
  when "beltline"
    score += 0.75 * weights[:property_type]
  end
  communities << apartment[:community].downcase
    
  if apartment[:community] == "Downtown"
    score += 1 * weights[:community]
  end
  
  case apartment[:property_type].downcase
  when "condo"
    score += 1 * weights[:property_type]
  when "apartment"
    score += 0.75 * weights[:property_type]
  end
  property_types << apartment[:property_type].downcase
  
  if apartment[:bedrooms] == "bachellor"
    score += 0.8 * weights[:bedrooms]
  else
    begin
      score += apartment[:bedrooms] * weights[:bedrooms]
    rescue TypeError
      puts "Unknown bedrooms: #{apartment[:bedrooms]}"
    end
  end
  
  score += apartment[:bathrooms] * weights[:bathrooms]
  
  score += weights[:under_18] if apartment[:under_18]
  score += weights[:pets] if apartment[:pets] || apartment[:dogs] || apartment[:cats]
  score += weights[:smoking] if apartment[:smoking]
  
  if apartment[:parking][:grade] == "underground" || apartment[:parking][:secure] = "secure" || apartment[:parking][:grade] == "garage"
    score += weights[:parking]
  end
  
  if apartment[:distance][:victoria_park] <= 2 || 
    apartment[:distance][:erlton] <= 2 ||
    apartment[:distance][:city_hall] <= 2
    apartment[:distance][:downtown] <= 2
    
    score += weights[:distance]
  end
  
  apartment[:analysis][:score] = score
end

puts "Communities: #{communities.uniq.sort.join(', ')}"

sorted = apartments.sort {|a,b| b[:analysis][:score] <=> a[:analysis][:score] }

sorted.each do |apartment|
  puts "#{apartment[:listing_number]}: #{apartment[:title]} Score: #{apartment[:analysis][:score]} Cost: #{apartment[:total_cost]}"
end