# VariantLab

A configurable eCommerce store built with Ruby on Rails and Solidus, designed to showcase complex product variant management, real-time pricing, and advanced filtering.

## Overview

VariantLab started as a laptop store and is architected to scale to any product category. It demonstrates real-world eCommerce engineering concepts including modular variant configuration, inventory management, and promotion logic.

## Tech Stack

- **Ruby on Rails 7.2** — backend framework
- **Solidus 4.x** — eCommerce engine
- **PostgreSQL** — primary database
- **Redis** — background job processing
- **Sidekiq** — async job queue
- **Tailwind CSS** — styling
- **Hotwire + Stimulus** — modern Rails frontend
- **Elasticsearch** — advanced filtering and search

## Features

- Configurable product variants — processor, RAM, storage, color
- Real-time price updates as variants are selected
- Advanced filtering by specs, price range, and use case
- Clean admin panel via Solidus
- Order management and inventory tracking
- Promotion and discount engine

## Local Setup

### Prerequisites

- Ruby 4.0.3
- PostgreSQL 17
- Redis
- Node.js

### Installation

```bash
git clone https://github.com/arielsalcepk/variantlab.git
cd variantlab
bundle install
rails db:create db:migrate db:seed
rails server
```

Visit `http://localhost:3000` to see the store.
Visit `http://localhost:3000/admin` for the admin panel.

### Admin credentials (development only)

- Email: `admin@variantlab.com`
- Password: `admin123`

## Architecture Decisions

**Why Solidus over Shopify?**
Solidus gives full control over the data model, business logic, and checkout flow. For a store with complex variant configurations and custom pricing rules, Solidus is the right tool.

**Why Rails 7.2 over 8?**
Solidus 4.x has a known compatibility issue with Rails 8's Propshaft asset pipeline. Rails 7.2 ships with Sprockets which Solidus supports cleanly. Will migrate when Solidus adds Propshaft support.

## Roadmap

- [ ] Tailwind custom storefront design
- [ ] Real-time variant price calculator with Stimulus
- [ ] Elasticsearch filtering by specs and price
- [ ] Comparison view for multiple laptops
- [ ] Sidekiq background jobs for order processing
- [ ] RSpec test coverage
- [ ] Additional product categories beyond laptops

## License

MIT