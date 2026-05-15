# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
Spree::Core::Engine.load_seed
Spree::Auth::Engine.load_seed

# ============================================================
# CLEAN SLATE — safe to run multiple times
# ============================================================
puts "Cleaning existing seed data..."

Spree::Product.destroy_all
Spree::OptionType.destroy_all
Spree::TaxCategory.destroy_all
Spree::ShippingCategory.destroy_all

# ============================================================
# SHIPPING & TAX CATEGORIES
# ============================================================
puts "Creating categories..."

shipping_category = Spree::ShippingCategory.create!(name: "Default")
tax_category = Spree::TaxCategory.create!(name: "Default", is_default: true)

# ============================================================
# OPTION TYPES
# ============================================================
puts "Creating option types..."

processor = Spree::OptionType.create!(name: "processor", presentation: "Processor")
ram = Spree::OptionType.create!(name: "ram", presentation: "RAM")
storage = Spree::OptionType.create!(name: "storage", presentation: "Storage")
color = Spree::OptionType.create!(name: "color", presentation: "Color")

# ============================================================
# OPTION VALUES
# ============================================================
puts "Creating option values..."

# Processors
m3 = Spree::OptionValue.create!(name: "m3", presentation: "M3", option_type: processor, position: 1)
m4 = Spree::OptionValue.create!(name: "m4", presentation: "M4", option_type: processor, position: 2)
m5 = Spree::OptionValue.create!(name: "m5", presentation: "M5", option_type: processor, position: 3)

# RAM
ram_16 = Spree::OptionValue.create!(name: "16gb", presentation: "16GB", option_type: ram, position: 1)
ram_32 = Spree::OptionValue.create!(name: "32gb", presentation: "32GB", option_type: ram, position: 2)
ram_64 = Spree::OptionValue.create!(name: "64gb", presentation: "64GB", option_type: ram, position: 3)

# Storage
ssd_256 = Spree::OptionValue.create!(name: "256gb", presentation: "256GB SSD", option_type: storage, position: 1)
ssd_512 = Spree::OptionValue.create!(name: "512gb", presentation: "512GB SSD", option_type: storage, position: 2)
ssd_1tb = Spree::OptionValue.create!(name: "1tb", presentation: "1TB SSD", option_type: storage, position: 3)

# Colors
space_black = Spree::OptionValue.create!(name: "space-black", presentation: "Space Black", option_type: color, position: 1)
silver = Spree::OptionValue.create!(name: "silver", presentation: "Silver", option_type: color, position: 2)
starlight = Spree::OptionValue.create!(name: "starlight", presentation: "Starlight", option_type: color, position: 3)

# ============================================================
# STOCK LOCATION
# ============================================================
puts "Creating stock location..."

stock_location = Spree::StockLocation.find_or_create_by!(
  name: "Warehouse",
  default: true,
  active: true
)

# ============================================================
# PRODUCT 1 — ARCBOOK PRO
# ============================================================
puts "Creating ArcBook Pro..."

arcbook_pro = Spree::Product.create!(
  name: "ArcBook Pro",
  description: "A high-performance modular laptop designed for professionals. Configure every component to match your exact workflow.",
  price: 999.00,
  available_on: Time.current,
  shipping_category: shipping_category,
  tax_category: tax_category
)

arcbook_pro.option_types << [ processor, ram, storage, color ]

# ArcBook Pro Variants
[
  { processor: m3, ram: ram_16, storage: ssd_256, color: space_black, price: 999.00,  sku: "ABP-M3-16-256-SB" },
  { processor: m3, ram: ram_16, storage: ssd_512, color: space_black, price: 1199.00, sku: "ABP-M3-16-512-SB" },
  { processor: m4, ram: ram_16, storage: ssd_512, color: space_black, price: 1399.00, sku: "ABP-M4-16-512-SB" },
  { processor: m4, ram: ram_32, storage: ssd_512, color: silver,      price: 1599.00, sku: "ABP-M4-32-512-SI" },
  { processor: m4, ram: ram_32, storage: ssd_1tb, color: silver,      price: 1799.00, sku: "ABP-M4-32-1TB-SI" },
  { processor: m5, ram: ram_32, storage: ssd_1tb, color: space_black, price: 1999.00, sku: "ABP-M5-32-1TB-SB" },
  { processor: m5, ram: ram_64, storage: ssd_1tb, color: starlight,   price: 2399.00, sku: "ABP-M5-64-1TB-ST" }
].each do |attrs|
  variant = Spree::Variant.create!(
    product: arcbook_pro,
    price: attrs[:price],
    sku: attrs[:sku]
  )
  variant.option_values << [ attrs[:processor], attrs[:ram], attrs[:storage], attrs[:color] ]
  stock_item = stock_location.stock_items.find_by(variant: variant)
  if stock_item
    stock_item.adjust_count_on_hand(10)
    stock_item.update!(backorderable: false)
  end
end

# ============================================================
# PRODUCT 2 — ARCBOOK AIR
# ============================================================
puts "Creating ArcBook Air..."

arcbook_air = Spree::Product.create!(
  name: "ArcBook Air",
  description: "The everyday laptop reimagined. Featherlight design meets serious performance for creators and professionals on the move.",
  price: 799.00,
  available_on: Time.current,
  shipping_category: shipping_category,
  tax_category: tax_category
)

arcbook_air.option_types << [ processor, ram, storage, color ]

[
  { processor: m3, ram: ram_16, storage: ssd_256, color: starlight,   price: 799.00,  sku: "ABA-M3-16-256-ST" },
  { processor: m3, ram: ram_16, storage: ssd_512, color: starlight,   price: 999.00,  sku: "ABA-M3-16-512-ST" },
  { processor: m3, ram: ram_16, storage: ssd_512, color: silver,      price: 1099.00, sku: "ABA-M3-16-512-SI" },
  { processor: m4, ram: ram_16, storage: ssd_512, color: space_black, price: 1299.00, sku: "ABA-M4-16-512-SB" },
  { processor: m4, ram: ram_32, storage: ssd_1tb, color: silver,      price: 1499.00, sku: "ABA-M4-32-1TB-SI" }
].each do |attrs|
  variant = Spree::Variant.create!(
    product: arcbook_air,
    price: attrs[:price],
    sku: attrs[:sku]
  )
  variant.option_values << [ attrs[:processor], attrs[:ram], attrs[:storage], attrs[:color] ]
  stock_item = stock_location.stock_items.find_by(variant: variant)
  if stock_item
    stock_item.adjust_count_on_hand(10)
    stock_item.update!(backorderable: false)
  end
end

# ============================================================
# PRODUCT 3 — ARCBOOK STUDIO
# ============================================================
puts "Creating ArcBook Studio..."

arcbook_studio = Spree::Product.create!(
  name: "ArcBook Studio",
  description: "Built for creators who refuse to compromise. Extreme performance for video editing, 3D rendering, and machine learning workloads.",
  price: 1999.00,
  available_on: Time.current,
  shipping_category: shipping_category,
  tax_category: tax_category
)

arcbook_studio.option_types << [ processor, ram, storage, color ]

[
  { processor: m4, ram: ram_32, storage: ssd_512, color: space_black, price: 1999.00, sku: "ABS-M4-32-512-SB" },
  { processor: m4, ram: ram_32, storage: ssd_1tb, color: space_black, price: 2199.00, sku: "ABS-M4-32-1TB-SB" },
  { processor: m4, ram: ram_64, storage: ssd_1tb, color: silver,      price: 2599.00, sku: "ABS-M4-64-1TB-SI" },
  { processor: m5, ram: ram_32, storage: ssd_1tb, color: space_black, price: 2799.00, sku: "ABS-M5-32-1TB-SB" },
  { processor: m5, ram: ram_64, storage: ssd_1tb, color: space_black, price: 3199.00, sku: "ABS-M5-64-1TB-SB" },
  { processor: m5, ram: ram_64, storage: ssd_1tb, color: starlight,   price: 3199.00, sku: "ABS-M5-64-1TB-ST" }
].each do |attrs|
  variant = Spree::Variant.create!(
    product: arcbook_studio,
    price: attrs[:price],
    sku: attrs[:sku]
  )
  variant.option_values << [ attrs[:processor], attrs[:ram], attrs[:storage], attrs[:color] ]
  stock_item = stock_location.stock_items.find_by(variant: variant)
  if stock_item
    stock_item.adjust_count_on_hand(10)
    stock_item.update!(backorderable: false)
  end
end

puts "Done! Created 3 products with variants."
