defmodule PinchflatWeb.Helpers.MarkdownHelpersTest do
  use ExUnit.Case, async: true

  alias PinchflatWeb.Helpers.MarkdownHelpers

  defp render(markdown) do
    {:safe, iodata} = MarkdownHelpers.to_html!(markdown)

    IO.iodata_to_binary(iodata)
  end

  describe "to_html!/1" do
    test "renders block and inline elements" do
      html = render("## Heading\n\nSome **bold** and `code` text.\n")

      assert html =~ "<h2"
      assert html =~ "Heading</h2>"
      assert html =~ "<strong"
      assert html =~ "bold</strong>"
      assert html =~ "code</code>"
    end

    test "renders both kinds of list" do
      html = render("- one\n- two\n\n1. first\n2. second\n")

      assert html =~ "<ul"
      assert html =~ "<ol"
      assert html =~ "one</li>"
      assert html =~ "first</li>"
    end

    test "attaches the app's classes to tags it knows about" do
      html = render("A paragraph.")

      assert html =~ ~s(<p class="mb-4 last:mb-0">)
    end

    test "replaces the classes the parser attaches on its own" do
      html = render("`code`\n\n---\n")

      refute html =~ "inline"
      refute html =~ "thin"
    end

    test "renders void elements without a closing tag" do
      html = render("above\n\n---\n\nbelow")

      assert html =~ "<hr class="
      refute html =~ "</hr>"
    end

    test "keeps attributes the parser produces" do
      html = render("[a link](https://example.com/page)")

      assert html =~ ~s(href="https://example.com/page")
    end

    test "opens external links in a new tab" do
      html = render("[a link](https://example.com/page)")

      assert html =~ ~s(target="_blank")
      assert html =~ ~s(rel="noopener noreferrer")
    end

    test "leaves relative links alone" do
      html = render("[a link](/sources)")

      refute html =~ "target="
    end

    test "escapes HTML in the source document" do
      html = render("a <script>alert('x')</script> tag")

      refute html =~ "<script>"
      assert html =~ "&lt;script&gt;"
    end

    test "returns a safe tuple so templates don't have to call raw/1" do
      assert {:safe, _iodata} = MarkdownHelpers.to_html!("hello")
    end
  end
end
