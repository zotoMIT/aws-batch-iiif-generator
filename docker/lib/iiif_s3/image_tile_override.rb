module IiifS3
  
  module ImageTileOverride

    protected

    def resize(width=nil,height=nil)
      @image.combine_options do |img|
        img.crop "#{@tile[:width]}x#{@tile[:height]}+#{@tile[:x]}+#{@tile[:y]}"
        img.resize "#{@tile[:xSize]}x#{@tile[:ySize]}"
        img.repage.+
      end
    end
  end
end
