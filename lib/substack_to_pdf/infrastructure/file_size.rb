# frozen_string_literal: true

module SubstackPdf
  module Infrastructure
    # Formats saved file sizes for user-facing messages.
    module FileSize
      MEGABYTE = 1_048_576

      module_function

      def format(path)
        megabytes = File.size(path).to_f / MEGABYTE
        Kernel.format("%.2f MB", megabytes)
      end
    end
  end
end
