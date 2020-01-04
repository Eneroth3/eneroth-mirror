# frozen_string_literal: true

module Eneroth
  module Mirror
    Sketchup.require "#{PLUGIN_ROOT}/mirror_tool"

    # Shortcut for creating command.
    #
    # @param name [String]
    # @param description [String, nil]
    # @param icon_basepath [String, nil]
    #   Icon path excluding file extension (and dot).
    #   SVG, PDF and PNG files on this path with this basename are expected,
    #   depending on what SU version and platform extension supports.
    #
    # @yield on user interaction.
    #
    # @return [UI::Command]
    def self.create_command(name, description = nil, icon_basepath = nil, &proc)
      command = UI::Command.new(name, &proc)
      command.tooltip = name
      command.status_bar_text = description if description

      if icon_basepath
        command.small_icon = command.large_icon =
          "#{icon_basepath}#{icon_file_extension}"
      end

      command
    end

    # Get icon file extension based on SketchUp version and platform.
    #
    # @return [String]
    def self.icon_file_extension
      if Sketchup.version.to_i < 16
        ".png"
      elsif Sketchup.platform == :platform_win
        ".svg"
      else
        ".pdf"
      end
    end

    # Show information page for a specific extension in Extension Warehouse.
    #
    # @param identifier [String] The extension identifier part of the URL to its
    #   information page. For the URL
    #   "http://extensions.sketchup.com/en/content/eneroth-align-face"
    #   "eneroth-align-face" should be passed as argument.
    #
    # @return [Void]
    def self.open_ew(identifier)
      # HACK: Use the skp:launchEW@ feature of the WebDialog class to launch EW.
      html = <<-HTML
        <a href="skp:launchEW@#{identifier}">Open EW</a>
        <script type="text/javascript">
          document.getElementsByTagName('a')[0].click();
        </script>
      HTML
      dlg = UI::WebDialog.new("Open EW", true, nil, 0, 0, 100_000, 0, true)
      dlg.set_html(html)
      dlg.show
    end

    # Check if Extension is licensed.
    #
    # This check is unsafe and only used for user feedback. The method can be
    # overridden. Additional checks with hardcoded extension IDs are done in
    # the business logic.
    #
    # @return [Boolean]
    def self.licensed?
      # TODO: Replace id.
      # TODO: Add additional licensing check elsewhere.
      identifier = "6b8d9d0f-3f8b-4101-9e0f-37dbf4372339"
      license = Sketchup::Licensing.get_extension_license(identifier)
      return true if license.licensed?

      message = OB["unlicensed", name: EXTENSION.name]
      return false unless UI.messagebox(message, MB_YESNO) == IDYES

      open_ew(EW_URL_ID)

      false
    end

    unless @loaded
      @loaded = true

      command_mirror = create_command(
        OB[:action_mirror],
        OB[:action_mirror_description],
        "#{PLUGIN_ROOT}/images/mirror"
      ) { MirrorTool.activate if licensed? }
      command_mirror.set_validation_proc { MirrorTool.command_state }

      menu = UI.menu("Plugins").add_submenu(EXTENSION.name)
      menu.add_item(command_mirror)
      menu.add_separator
      OB.lang_menu(
        menu.add_submenu(OB[:lang_option]),
        system_lang_name: OB[:system_lang_name]
      )

      toolbar = UI::Toolbar.new(EXTENSION.name)
      toolbar.add_item(command_mirror)
      toolbar.restore
    end
  end
end
