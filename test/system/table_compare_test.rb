require "application_system_test_case"

# "Compare from the table": turn on compare mode, select up to 2 models
# directly in the homepage price table, gather them in a sticky bottom tray,
# and open a head-to-head comparison as an in-page <dialog> + Turbo Frame that
# loads the existing /compare page — these journeys exercise that whole loop,
# plus the
# one correctness property that matters most: navigating inside the modal
# must never leave root_path (see compare_controller.js#_navigate).
class TableCompareTest < ApplicationSystemTestCase
  # All 7 fixture models' rows need to be reachable without the fixed bottom
  # price-change ticker (and, once a model is selected, the fixed compare
  # tray) covering the row being interacted with — taller than the shared
  # desktop default so every row clears both bars without scroll gymnastics.
  # The hero's mini-timeline of recent market events grew the homepage's
  # above-the-fold height by ~170px, so this needs a bit more headroom on
  # top of that to keep clicks on the fixed compare tray unambiguous.
  setup { page.current_window.resize_to(1400, 2200) }

  test "selecting 2 rows shows the tray with both slots filled" do
    visit root_path

    select_in_table "Claude Opus 4.8"
    select_in_table "DeepSeek V4 Pro"

    within ".tp-tray" do
      assert_text "Claude Opus 4.8"
      assert_text "DeepSeek V4 Pro"
      assert_selector ".tp-tray-slot.filled", count: 2
      assert_no_button "Pick one more"
      assert_button "Compare"
    end
  end

  test "selecting a 3rd model drops the oldest (FIFO)" do
    visit root_path

    select_in_table "Claude Opus 4.8"
    select_in_table "DeepSeek V4 Pro"
    select_in_table "Guide Haiku Fixture"

    within ".tp-tray" do
      assert_no_text "Claude Opus 4.8"
      assert_text "DeepSeek V4 Pro"
      assert_text "Guide Haiku Fixture"
    end
  end

  test "removing a model via the tray's x updates the Compare button's disabled state" do
    visit root_path

    select_in_table "Claude Opus 4.8"
    select_in_table "DeepSeek V4 Pro"

    within ".tp-tray" do
      assert_button "Compare"
      find(".tp-tray-slot-remove[aria-label='Remove DeepSeek V4 Pro']").click
      assert_no_text "DeepSeek V4 Pro"
      assert_text "Claude Opus 4.8"
      assert_button "Pick one more", disabled: true
    end
  end

  test "Clear empties the tray and hides it" do
    visit root_path

    select_in_table "Claude Opus 4.8"
    select_in_table "DeepSeek V4 Pro"

    within ".tp-tray" do
      click_on "Clear"
    end

    assert_no_selector ".tp-tray", visible: true
  end

  test "clicking Compare opens the dialog with the winner-highlighted comparison content" do
    visit root_path

    select_in_table "Claude Opus 4.8"
    select_in_table "DeepSeek V4 Pro"
    within ".tp-tray" do
      click_on "Compare"
    end

    within "dialog.tp-compare-dialog" do
      assert_selector ".cmp-table"
      assert_selector ".sel-btn-name", text: "Claude Opus 4.8"
      assert_selector ".sel-btn-name", text: "DeepSeek V4 Pro"
      assert_selector ".cmp-cell.win", minimum: 1
    end
    assert_current_path root_path
  end

  test "Esc closes the dialog" do
    visit root_path
    open_dialog_for("Claude Opus 4.8", "DeepSeek V4 Pro")

    find("body").send_keys(:escape)

    assert_no_selector "dialog.tp-compare-dialog[open]"
  end

  test "the close button closes the dialog" do
    visit root_path
    open_dialog_for("Claude Opus 4.8", "DeepSeek V4 Pro")

    within "dialog.tp-compare-dialog" do
      find(".tp-compare-dialog-close").click
    end

    assert_no_selector "dialog.tp-compare-dialog[open]"
  end

  test "backdrop click closes the dialog" do
    visit root_path
    open_dialog_for("Claude Opus 4.8", "DeepSeek V4 Pro")

    # Click a point outside the centered dialog panel but still inside the
    # viewport, landing on the ::backdrop. move_to is relative to the viewport
    # origin (unlike move_by, which is relative to the cursor's last position).
    page.driver.browser.action.move_to_location(10, 10).click.perform

    assert_no_selector "dialog.tp-compare-dialog[open]"
  end

  test "swap inside the modal does not navigate away from root_path" do
    visit root_path
    open_dialog_for("Claude Opus 4.8", "DeepSeek V4 Pro")

    within "dialog.tp-compare-dialog" do
      find('[data-compare-target="swapBtn"]').click
      within '[data-compare-target="btnA"]' do
        assert_text "DeepSeek V4 Pro"
      end
    end

    assert_current_path root_path
  end

  test "pick inside the modal does not navigate away from root_path" do
    visit root_path
    open_dialog_for("Claude Opus 4.8", "DeepSeek V4 Pro")

    within "dialog.tp-compare-dialog" do
      find('[data-compare-target="btnA"]').click
      within '[data-compare-target="popA"]' do
        find("input[placeholder='Search models…']").set("Guide Haiku")
        click_on "Guide Haiku Fixture"
      end

      assert_selector ".sel-btn-name", text: "Guide Haiku Fixture"
    end

    assert_current_path root_path
  end

  test "selecting a model then changing a filter preserves the selection" do
    visit root_path

    select_in_table "Claude Opus 4.8"

    fill_in "q", with: "claude"

    within "#models" do
      assert_text "Claude Opus 4.8"
    end

    within ".tp-tray" do
      assert_text "Claude Opus 4.8"
    end
    within "#models" do
      assert_selector "tr.tp-row-selected", text: "Claude Opus 4.8"
    end
  end

  private

  # Compare is opt-in: the select column is hidden until the "Compare models"
  # toggle turns compare mode on. Ensure the mode is on (idempotently — a test
  # selects several rows, and toggling per call would flip it back off), then
  # click the now-visible, persistent select button.
  def select_in_table(model_name)
    ensure_compare_mode
    row = find("table.tp-data tbody tr", text: model_name)
    row.find(".tp-select-btn").click
  end

  def ensure_compare_mode
    return if page.has_css?("[data-controller='compare-tray'].compare-active", wait: 0)
    click_button "Compare models"
    assert_selector "[data-controller='compare-tray'].compare-active"
  end

  def open_dialog_for(model_a, model_b)
    select_in_table(model_a)
    select_in_table(model_b)
    within ".tp-tray" do
      click_on "Compare"
    end
    assert_selector "dialog.tp-compare-dialog[open] .cmp-table"
  end
end
