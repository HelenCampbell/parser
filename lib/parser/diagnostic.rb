module Parser

  ##
  # @api public
  #
  # @!attribute [r] level
  #  @see LEVELS
  #  @return [Symbol] diagnostic level
  #
  # @!attribute [r] reason
  #  @see Parser::MESSAGES
  #  @return [Symbol] reason for error
  #
  # @!attribute [r] arguments
  #  @see Parser::MESSAGES
  #  @return [Symbol] extended arguments that describe the error
  #
  # @!attribute [r] message
  #  @return [String] error message
  #
  # @!attribute [r] location
  #  Main error-related source range.
  #  @return [Parser::Source::Range]
  #
  # @!attribute [r] highlights
  #  Supplementary error-related source ranges.
  #  @return [Array<Parser::Source::Range>]
  #
  class Diagnostic
    ##
    # Collection of the available diagnostic levels.
    #
    # @return [Array]
    #
    LEVELS = [:note, :warning, :error, :fatal].freeze

    attr_reader :level, :reason, :arguments
    attr_reader :location, :highlights

    ##
    # @param [Symbol] level
    # @param [Symbol] reason
    # @param [Hash] arguments
    # @param [Parser::Source::Range] location
    # @param [Array<Parser::Source::Range>] highlights
    #
    def initialize(level, reason, arguments, location, highlights=[])
      unless LEVELS.include?(level)
        raise ArgumentError,
              "Diagnostic#level must be one of #{LEVELS.join(', ')}; " \
              "#{level.inspect} provided."
      end
      raise 'Expected a location' unless location

      @level       = level
      @reason      = reason
      @arguments   = (arguments || {}).dup.freeze
      @location    = location
      @highlights  = highlights.dup.freeze

      freeze
    end

    ##
    # @return [String] the rendered message.
    #
    def message
      MESSAGES[@reason] % @arguments
    end

    ##
    # Renders the diagnostic message as a clang-like diagnostic.
    #
    # @example
    #  diagnostic.render # =>
    #  # [
    #  #   "(fragment:0):1:5: error: unexpected token $end",
    #  #   "foo +",
    #  #   "    ^"
    #  # ]
    #
    # @return [Array<String>]
    #
    def render
      if @location.line != @location.last_line
        # multi-line diagnostic
        first_line = first_line_only(@location)
        last_line  = last_line_only(@location)
        buffer     = @location.source_buffer

        first_lineno, first_column = buffer.decompose_position(@location.begin_pos)
        last_lineno,  last_column  = buffer.decompose_position(@location.end_pos)

        ["#{@location}-#{last_lineno}:#{last_column}: #{@level}: #{message}"] +
          render_line(first_line).
            map { |line| "#{buffer.name}:#{first_lineno}: #{line}" }.
            tap { |array| array.last << '...' } +
          render_line(last_line).map  { |line| "#{buffer.name}:#{last_lineno}: #{line}" }
      else
        ["#{@location}: #{@level}: #{message}"] + render_line(@location)
      end
    end

    private

    ##
    # Renders one source line in clang diagnostic style, with highlights.
    #
    # @return [Array<String>]
    #
    def render_line(range)
      source_line    = range.source_line
      highlight_line = ' ' * source_line.length

      @highlights.each do |hilight|
       line_range = range.source_buffer.line_range(range.line)
        if hilight = hilight.intersect(line_range)
          highlight_line[hilight.column_range] = '~' * hilight.size
        end
      end

      highlight_line[range.column_range] = '^' * range.size

      [source_line, highlight_line]
    end

    ##
    # If necessary, shrink a `Range` so as to include only the first line.
    #
    # @return [Parser::Source::Range]
    #
    def first_line_only(range)
      if range.line != range.last_line
        range.resize(range.source =~ /\n/)
      else
        range
      end
    end

    ##
    # If necessary, shrink a `Range` so as to include only the last line.
    #
    # @return [Parser::Source::Range]
    #
    def last_line_only(range)
      if range.line != range.last_line
        Source::Range.new(range.source_buffer,
                          range.begin_pos + (range.source =~ /[^\n]*\Z/),
                          range.end_pos)
      else
        range
      end
    end
  end
end
