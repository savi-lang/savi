struct Clang::Cursor
  # The upstream code doesn't deal with null pointers correctly,
  # so we have copied the code here and included an explicit null check.
  def brief_comment_text
    if (ptr = LibC.clang_Cursor_getBriefCommentText(self)) && !ptr.data.null?
      Clang.string(ptr)
    end
  end
  def raw_comment_text
    if (ptr = LibC.clang_Cursor_getRawCommentText(self)) && !ptr.data.null?
      Clang.string(ptr)
    end
  end
end
