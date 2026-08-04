defmodule PinchflatWeb.CustomComponents.ButtonComponents do
  @moduledoc false
  use Phoenix.Component, global_prefixes: ~w(x-)

  alias PinchflatWeb.CoreComponents
  alias PinchflatWeb.CustomComponents.TextComponents

  @doc """
  Render a button

  ## Examples

      <.button color="bg-primary" rounding="rounded-xs">
        <span>Click me</span>
      </.button>
  """
  attr :color, :string, default: "bg-primary"
  attr :rounding, :string, default: "rounded-xs"
  attr :class, :string, default: ""
  attr :type, :string, default: "submit"
  attr :disabled, :boolean, default: false
  attr :rest, :global

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      class={[
        "text-center font-medium text-white whitespace-nowrap",
        "#{@rounding} inline-flex items-center justify-center px-8 py-4",
        "#{@color}",
        "hover:opacity-90 lg:px-8 xl:px-10",
        "disabled:opacity-50 disabled:cursor-not-allowed disabled:text-grey-5",
        @class
      ]}
      type={@type}
      disabled={@disabled}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Render a dropdown based off a button

  ## Examples

      <.button_dropdown text="Actions">
        <:option>TEST</:option>
      </.button_dropdown>
  """
  attr :text, :string, required: true
  attr :class, :string, default: ""

  slot :option, required: true

  def button_dropdown(assigns) do
    ~H"""
    <div x-data="{ dropdownOpen: false }" class={["relative flex", @class]}>
      <span
        x-on:click.prevent="dropdownOpen = !dropdownOpen"
        class={[
          "cursor-pointer inline-flex gap-2.5 rounded-md bg-primary px-5.5 py-3",
          "font-medium text-white hover:bg-primary/95"
        ]}
      >
        {@text}
        <CoreComponents.icon
          name="hero-chevron-down"
          class="fill-current duration-200 ease-linear mt-1"
          x-bind:class="dropdownOpen && 'rotate-180'"
        />
      </span>
      <div
        x-show="dropdownOpen"
        x-on:click.outside="dropdownOpen = false"
        class="absolute left-0 top-full z-40 mt-2 w-full rounded-md bg-black py-3 shadow-card"
      >
        <ul class="flex flex-col">
          <li :for={option <- @option}>
            <span class="flex px-5 py-2 font-medium text-bodydark2 hover:text-white cursor-pointer">
              {render_slot(option)}
            </span>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  @doc """
  Render a button with an icon. Optionally include a tooltip.

  ## Examples

      <.icon_button icon_name="hero-check" tooltip="Complete" />
  """
  attr :icon_name, :string, required: true
  attr :class, :string, default: ""
  attr :tooltip, :string, default: nil
  attr :rest, :global, include: ~w(disabled type)

  def icon_button(assigns) do
    ~H"""
    <TextComponents.tooltip position="bottom" tooltip={@tooltip} tooltip_class="text-nowrap">
      <button
        class={[
          "flex justify-center items-center rounded-lg ",
          "bg-form-input border-2 border-strokedark",
          "hover:bg-meta-4 hover:border-form-strokedark",
          @class
        ]}
        type="button"
        {@rest}
      >
        <CoreComponents.icon name={@icon_name} class="text-stroke" />
      </button>
    </TextComponents.tooltip>
    """
  end

  @doc """
  A single item in a page header's ⋯ Actions menu: an icon, a title, and a
  one-line description. Renders as a `.link` so it supports POST/DELETE actions
  with an optional confirmation dialog.

  `variant="danger"` tints the whole row (icon, title, description, hover) for
  destructive actions, so a Danger zone reads as one red block while keeping the
  same two-line shape as every other item.
  """
  attr :href, :string, required: true
  attr :method, :string, default: "get"
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :confirm, :string, default: nil
  attr :variant, :string, default: "default", values: ~w(default danger)

  def action_item(assigns) do
    ~H"""
    <.link
      href={@href}
      method={@method}
      data-confirm={@confirm}
      class={[
        "flex items-start gap-3 px-4 py-2.5",
        @variant == "danger" && "text-danger hover:bg-danger/10",
        @variant != "danger" && "text-bodydark2 hover:bg-meta-4 hover:text-white"
      ]}
    >
      <CoreComponents.icon name={@icon} class="mt-0.5 h-5 w-5 shrink-0" />
      <span class="flex flex-col">
        <span class={["font-medium whitespace-nowrap", @variant != "danger" && "text-white"]}>{@title}</span>
        <span class={[
          "text-sm whitespace-nowrap",
          if(@variant == "danger", do: "text-danger/70", else: "text-bodydark2")
        ]}>
          {@description}
        </span>
      </span>
    </.link>
    """
  end

  @doc """
  A client-side-only switch bound to an Alpine boolean, styled to match the
  form toggle in `CoreComponents.input/1` at a smaller scale. Unlike that one
  this has no form field behind it — the real checkbox is visually hidden and
  drives the Alpine state, which keeps the label clickable and the control
  reachable by keyboard.
  """
  attr :model, :string, required: true, doc: "the Alpine expression to bind (e.g. \"showUnset\")"
  attr :label, :string, required: true

  def switch(assigns) do
    ~H"""
    <label class="group flex cursor-pointer select-none items-center gap-2.5 text-sm text-bodydark hover:text-black dark:hover:text-white">
      <input type="checkbox" x-model={@model} class="peer sr-only" />
      <span class="relative inline-block h-5 w-9 shrink-0">
        <span
          class="block h-full w-full rounded-full bg-stroke transition peer-focus-visible:ring-2 peer-focus-visible:ring-primary dark:bg-strokedark"
          x-bind:class={"#{@model} && 'bg-primary! dark:bg-primary!'"}
        ></span>
        <span
          class="absolute left-0.5 top-0.5 h-4 w-4 rounded-full bg-white shadow transition"
          x-bind:class={"#{@model} && 'translate-x-4'"}
        ></span>
      </span>
      {@label}
    </label>
    """
  end

  @doc """
  A compact two-or-more-option segmented control bound to an Alpine expression.
  Each option is a `{label, alpine_value}` pair — the value is written into the
  bound expression verbatim, so it must be a JS literal (`"true"`, `"'json'"`).
  """
  attr :model, :string, required: true
  attr :options, :list, required: true
  attr :aria_label, :string, default: nil

  def segmented_control(assigns) do
    ~H"""
    <div
      role="group"
      aria-label={@aria_label}
      class="inline-flex items-center gap-0.5 rounded-md border border-stroke p-0.5 dark:border-strokedark"
    >
      <button
        :for={{label, value} <- @options}
        type="button"
        x-on:click={"#{@model} = #{value}"}
        x-bind:class={"#{@model} === #{value} ? 'bg-meta-4 text-white' : 'text-bodydark hover:text-black dark:hover:text-white'"}
        x-bind:aria-pressed={"#{@model} === #{value}"}
        class="rounded-sm px-2.5 py-1 text-xs font-medium transition"
      >
        {label}
      </button>
    </div>
    """
  end
end
