defmodule PinchflatWeb.Helpers.MarkdownHelpers do
  @moduledoc """
  Renders a Markdown document to HTML styled with the app's Tailwind classes.

  This is deliberately not a general-purpose Markdown pipeline. It walks the
  `EarmarkParser` AST and emits the tags itself so each one can be given the
  project's own classes as it goes - there's no Tailwind typography plugin here
  to lean on, and a `prose`-style block of descendant selectors would have to
  guess at the same set of tags anyway. A tag with no class defined still
  renders; it just renders unstyled.

  Intended for documents that ship with the app and are rendered at compile
  time (see `Pinchflat.Settings.UserAgreement`), not for user input.
  """

  @classes %{
    "h1" => "mb-4 text-xl font-bold text-black dark:text-white",
    "h2" => "mb-2 mt-6 text-base font-bold text-black first:mt-0 dark:text-white",
    "h3" => "mb-2 mt-4 font-bold text-black first:mt-0 dark:text-white",
    "h4" => "mb-2 mt-4 font-bold text-black first:mt-0 dark:text-white",
    "p" => "mb-4 last:mb-0",
    "ul" => "mb-4 list-disc space-y-2 pl-6",
    "ol" => "mb-4 list-decimal space-y-2 pl-6",
    "li" => "pl-1",
    "strong" => "font-bold text-black dark:text-white",
    "em" => "italic",
    "a" => "text-primary underline hover:no-underline",
    "code" => "rounded-xs bg-black/5 px-1 py-0.5 font-mono text-xs dark:bg-white/10",
    "pre" => "mb-4 overflow-x-auto rounded-xs bg-black/5 p-3 text-xs dark:bg-white/10",
    "blockquote" => "mb-4 border-l-4 border-stroke pl-4 italic dark:border-strokedark",
    "hr" => "my-6 border-t border-stroke dark:border-strokedark",
    "table" => "mb-4 w-full text-left",
    "th" => "border border-stroke px-2 py-1 font-bold dark:border-strokedark",
    "td" => "border border-stroke px-2 py-1 dark:border-strokedark"
  }

  @void_elements ~w(area base br col embed hr img input link meta source track wbr)

  @doc """
  Converts a Markdown string into a `{:safe, iodata}` tuple, ready to be
  rendered in a template.

  Raises on Markdown the parser rejects outright, which is the behaviour you
  want when this runs at compile time - a malformed document fails the build
  rather than rendering as a broken page.

  Returns Phoenix.HTML.safe()
  """
  def to_html!(markdown) do
    case EarmarkParser.as_ast(markdown) do
      {:ok, ast, _messages} ->
        {:safe, render(ast)}

      {:error, _ast, messages} ->
        raise "Could not parse Markdown: #{inspect(messages)}"
    end
  end

  defp render(nodes) when is_list(nodes), do: Enum.map(nodes, &render/1)
  defp render(text) when is_binary(text), do: escape(text)

  # Comments and other non-tag nodes (`{:comment, _, _, _}`) are dropped rather
  # than passed through - nothing in an app-shipped document needs them.
  defp render({tag, _attrs, _children, _meta}) when not is_binary(tag), do: []

  defp render({tag, attrs, children, _meta}) do
    attrs = attrs |> normalize_attrs(tag) |> render_attrs()

    if tag in @void_elements do
      ["<", tag, attrs, ">"]
    else
      ["<", tag, attrs, ">", render(children), "</", tag, ">"]
    end
  end

  defp normalize_attrs(attrs, tag) do
    attrs
    |> put_classes(tag)
    |> put_link_target(tag)
  end

  # Ours replace rather than merge with whatever the parser attached, since
  # EarmarkParser puts its own presentational classes on some tags (`thin` on
  # `hr`, `inline` on `code`) that mean nothing here and can collide with
  # Tailwind utilities of the same name.
  defp put_classes(attrs, tag) do
    case Map.fetch(@classes, tag) do
      :error -> attrs
      {:ok, class} -> [{"class", class} | List.keydelete(attrs, "class", 0)]
    end
  end

  # Documents rendered here are shown in contexts the user shouldn't be
  # navigated away from (the agreement gate is a full-page dialog), so external
  # links open in a new tab.
  defp put_link_target(attrs, "a") do
    case List.keyfind(attrs, "href", 0) do
      {"href", "http" <> _} -> attrs ++ [{"target", "_blank"}, {"rel", "noopener noreferrer"}]
      _ -> attrs
    end
  end

  defp put_link_target(attrs, _tag), do: attrs

  defp render_attrs(attrs) do
    Enum.map(attrs, fn {name, value} ->
      [" ", name, "=\"", escape(to_string(value)), "\""]
    end)
  end

  defp escape(text), do: Phoenix.HTML.Engine.encode_to_iodata!(text)
end
