class Termisu::Terminal
  struct Cursor
    property x : Int32 = 0
    property y : Int32 = 0
    property? visible : Bool
    property shape : Shape = Shape::Default

    def initialize(@visible = false)
    end

    enum Shape : UInt8
      Default           = 0
      BlinkingBlock     = 1
      Block             = 2
      BlinkingUnderline = 3
      Underline         = 4
      BlinkingBar       = 5
      Bar               = 6
    end
  end

  private def apply_cursor_state
    x, y = @cursor.x, @cursor.y
    @cursor.x, @cursor.y = -1, -1
    move_cursor(x, y)

    visible = @cursor.visible?
    @cursor.visible = !visible
    set_cursor visible
  end

  def hide_cursor
    set_cursor visible: false
  end

  def show_cursor
    set_cursor visible: true
  end

  def set_cursor(
    visible : Bool? = nil,
    shape : Cursor::Shape? = nil,
  )
    visible = @cursor.visible? if visible.nil?
    shape = @cursor.shape if shape.nil?

    if visible
      unless @cursor.visible?
        write(@terminfo.show_cursor_seq)
      end
      unless @cursor.visible? && shape == @cursor.shape
        # DECSCUSR carries the preferred cursor shape+blink state, while cvvis is
        # sent as a compatibility shim for terminals that still honor the legacy
        # terminfo blink capability. tmux, Alacritty, and Neovim can treat these
        # sequences differently, so keep both for now and re-check behavior before
        # dropping the terminfo path.
        # Follow-up: validate cursor shape/blink behavior across supported
        # terminals and remove blink_cursor_seq when DECSCUSR support is reliable.
        write("\e[#{@cursor.shape.value} q")
        write(@terminfo.blink_cursor_seq) if @cursor.shape.value.in?(1, 3, 5)
      end
    elsif @cursor.visible?
      write(@terminfo.hide_cursor_seq)
    end

    @cursor.shape = shape
    @cursor.visible = visible
  end

  def move_cursor(
    x : Int32 = @cursor.x,
    y : Int32 = @cursor.y,
  )
    width, height = @size
    return if width <= 0 || height <= 0

    x = x.clamp(0, width - 1)
    y = y.clamp(0, height - 1)

    return if x == @cursor.x && y == @cursor.y

    seq = @terminfo.cursor_position_seq(y, x)
    write(seq.empty? ? "\e[#{y + 1};#{x + 1}H" : seq)

    @cursor.x, @cursor.y = x, y
  end

  private def with_ephemeral_cursor(visible : Bool = false, &)
    cursor_backup = @cursor
    @cursor = Cursor.new visible
    apply_cursor_state
    begin
      yield
    ensure
      @cursor = cursor_backup
      apply_cursor_state
    end
  end

  # Write *data* to the terminal. Use *columns_advanced* to specify how
  # much this will move the cursor to the right. If this would move the
  # cursor beyond the terminal's width, it will wrap into the next line
  def write(data : String, columns_advanced = 0)
    @backend.write(data)

    width, height = @size
    return if width <= 0 || height <= 0

    x = @cursor.x + columns_advanced

    @cursor.x = x % width
    @cursor.y = (@cursor.y + x // width).clamp(0, height - 1)
  end
end
