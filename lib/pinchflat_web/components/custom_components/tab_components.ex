defmodule PinchflatWeb.CustomComponents.TabComponents do
  @moduledoc false
  use Phoenix.Component

  @doc """
  Takes a list of tabs and renders them in a tabbed layout.
  """
  slot :tab, required: true do
    attr :id, :string, required: true
    attr :title, :string, required: true
    attr :count, :integer, doc: "optional count badge rendered next to the tab title"

    attr :error_count, :integer,
      doc: "optional second, danger-tinted badge for entries needing attention. Hidden when 0 or nil"

    attr :align, :string, doc: "set to \"end\" to push this (and following) tabs to the right"
  end

  attr :default_tab, :string, default: nil, doc: "id of the tab shown when the URL has no tab hash"

  slot :tab_append, required: false

  def tabbed_layout(assigns) do
    default_tab_id = assigns[:default_tab] || hd(assigns.tab).id
    # Passed to the hash reader so a `#tab-whatever` naming a tab this page doesn't
    # have falls back to the default instead of showing an empty panel
    tab_ids = "[" <> Enum.map_join(assigns.tab, ", ", &"'#{&1.id}'") <> "]"

    assigns = assigns |> Map.put(:default_tab_id, default_tab_id) |> Map.put(:tab_ids, tab_ids)

    ~H"""
    <div
      x-data={"{
        openTab: getTabFromHash('#{@default_tab_id}', '#{@default_tab_id}', #{@tab_ids}),
        activeClasses: 'text-meta-5 border-meta-5',
        inactiveClasses: 'border-transparent'
      }"}
      @hashchange.window={"openTab = getTabFromHash(openTab, '#{@default_tab_id}', #{@tab_ids})"}
      class="w-full"
    >
      <header class="flex flex-col md:flex-row md:justify-between border-b border-strokedark">
        <div class="flex flex-wrap gap-5 sm:gap-10">
          <a
            :for={tab <- @tab}
            href="#"
            @click.prevent={"openTab = setTabByName('#{tab.id}')"}
            x-bind:class={"openTab === '#{tab.id}' ? activeClasses : inactiveClasses"}
            class={[
              "border-b-2 py-4 w-full sm:w-fit text-sm font-medium hover:text-meta-5 md:text-base",
              Map.get(tab, :align) == "end" && "sm:ml-auto"
            ]}
          >
            <span class="text-xl">{tab.title}</span>
            <span
              :if={not is_nil(Map.get(tab, :count))}
              class="ml-1.5 inline-flex items-center rounded-full bg-meta-4 px-2 py-0.5 text-sm font-medium text-bodydark1"
            >
              {tab.count}
            </span>
            <span
              :if={(Map.get(tab, :error_count) || 0) > 0}
              title="Needs attention"
              class="ml-1.5 inline-flex items-center rounded-full bg-danger/15 px-2 py-0.5 text-sm font-medium text-danger"
            >
              {tab.error_count}
            </span>
          </a>
        </div>
        <div class="mx-4 my-4 lg:my-0 flex gap-5 sm:gap-10 items-center">
          {render_slot(@tab_append)}
        </div>
      </header>
      <div class="mt-4 min-h-60 overflow-x-auto">
        <div :for={tab <- @tab} x-show={"openTab === '#{tab.id}'"} class="font-medium leading-relaxed">
          {render_slot(tab)}
        </div>
      </div>
    </div>
    """
  end
end
