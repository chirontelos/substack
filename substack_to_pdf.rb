#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/substack_to_pdf"

exit SubstackPdf::CLI.new(ARGV).run
