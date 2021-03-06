# encoding: UTF-8
require 'test_helper'

class GovspeakHelperTest < ActionView::TestCase
  include PublicDocumentRoutesHelper

  setup do
    @request  = ActionController::TestRequest.new
    ActionController::Base.default_url_options = {}
  end
  attr_reader :request

  test "should not alter urls to other sites" do
    html = govspeak_to_html("no [change](http://external.example.com/page.html)")
    assert_select_within_html html, "a[href=?]", "http://external.example.com/page.html", text: "change"
  end

  test "should not alter mailto urls" do
    html = govspeak_to_html("no [change](mailto:dave@example.com)")
    assert_select_within_html html, "a[href=?]", "mailto:dave@example.com", text: "change"
  end

  test "should not alter invalid urls" do
    html = govspeak_to_html("no [change](not a valid url)")
    assert_select_within_html html, "a[href=?]", "not a valid url", text: "change"
  end

  test "should not alter partial urls" do
    html = govspeak_to_html("no [change](http://)")
    assert_select_within_html html, "a[href=?]", "http://", text: "change"
  end

  test "should wrap output with a govspeak class" do
    html = govspeak_to_html("govspeak-text")
    assert_select_within_html html, ".govspeak", text: "govspeak-text"
  end

  test "should mark the govspeak output as html safe" do
    html = govspeak_to_html("govspeak-text")
    assert html.html_safe?
  end

  test "should produce UTF-8 for HTML entities" do
    html = govspeak_to_html("a ['funny'](/url) thing")
    assert_select_within_html html, "a", text: "‘funny’"
  end

  test "should not mark admin links as 'external'" do
    request.host = public_preview_host
    speech = create(:published_speech)
    url = admin_speech_url(speech, host: request.host)
    govspeak = "this and [that](#{url}) yeah?"
    html = govspeak_to_html(govspeak)
    refute_select_within_html html, "a[rel='external']", text: "that"
  end

  test "should not mark public preview links as 'external'" do
    speech = create(:published_speech)
    url = admin_speech_url(speech, host: public_preview_host)
    govspeak = "this and [that](#{url}) yeah?"
    html = govspeak_to_html(govspeak)
    refute_select_within_html html, "a[rel='external']", text: "that"
  end

  test "should not mark main site links as 'external'" do
    speech = create(:published_speech)
    url = admin_speech_url(speech, host: public_production_host)
    govspeak = "this and [that](#{url}) yeah?"
    html = govspeak_to_html(govspeak)
    refute_select_within_html html, "a[rel='external']", text: "that"
  end

  test "should allow attached images to be embedded in public html" do
    images = [OpenStruct.new(alt_text: "My Alt", url: "http://example.com/image.jpg")]
    html = govspeak_to_html("!!1", images)
    assert_select_within_html html, ".govspeak figure.image.embedded img"
  end

  test "should only extract level two headers by default" do
    text = "# Heading 1\n\n## Heading 2\n\n### Heading 3"
    headers = govspeak_headers(text)
    assert_equal [Govspeak::Header.new("Heading 2", 2, "heading-2")], headers
  end

  test "should extract header hierarchy from level 2+3 headings" do
    text = "# Heading 1\n\n## Heading 2a\n\n### Heading 3a\n\n### Heading 3b\n\n#### Ignored heading\n\n## Heading 2b"
    headers = govspeak_header_hierarchy(text)
    assert_equal [
      {
        header: Govspeak::Header.new("Heading 2a", 2, "heading-2a"),
        children: [
          Govspeak::Header.new("Heading 3a", 3, "heading-3a"),
          Govspeak::Header.new("Heading 3b", 3, "heading-3b")
        ]
      },
      {
        header: Govspeak::Header.new("Heading 2b", 2, "heading-2b"),
        children: []
      }
    ], headers
  end

  test "should raise exception when extracting header hierarchy with orphaned level 3 headings" do
    e = assert_raises(OrphanedHeadingError) { govspeak_header_hierarchy("### Heading 3") }
    assert_equal "Heading 3", e.heading
  end

  test "should convert single document to govspeak" do
    document = build(:published_policy, body: "## test")
    html = govspeak_edition_to_html(document)
    assert_select_within_html html, "h2"
  end

  test "should optionally not wrap output in a govspeak class" do
    document = build(:published_policy, body: "govspeak-text")
    html = bare_govspeak_edition_to_html(document)
    assert_select_within_html html, ".govspeak", false
    assert_select_within_html html, "p", "govspeak-text"
  end

  test "should add block attachments inline" do
    text = "#Heading\n\n!@1\n\n##Subheading"
    document = build(:published_detailed_guide, :with_attachment, body: text)
    html = govspeak_edition_to_html(document)
    assert_select_within_html html, "h1"
    assert_select_within_html html, ".attachment.embedded"
    assert_select_within_html html, "h2"
  end

  test "should add inline attachments inline" do
    text = "#Heading\n\nText about my [InlineAttachment:1]."
    document = build(:published_detailed_guide, :with_attachment, body: text)
    html = govspeak_edition_to_html(document)
    assert_select_within_html html, "h1"
    assert_select_within_html html, ".attachment.inline"
  end

  test "should ignore missing block attachments" do
    text = "#Heading\n\n!@2\n\n##Subheading"
    document = build(:published_detailed_guide, :with_attachment, body: text)
    html = govspeak_edition_to_html(document)
    assert_select_within_html html, "h1"
    refute_select_within_html html, ".attachment.embedded"
    assert_select_within_html html, "h2"
  end

  test "should ignore missing inline attachments" do
    text = "#Heading\n\nText about my [InlineAttachment:2]."
    document = build(:published_detailed_guide, :with_attachment, body: text)
    html = govspeak_edition_to_html(document)
    assert_select_within_html html, "h1"
    refute_select_within_html html, ".attachment.inline"
  end

  test "should not convert documents with no block attachments" do
    text = "#Heading\n\n!@2"
    document = build(:published_detailed_guide, body: text)
    html = govspeak_edition_to_html(document)
    refute_select_within_html html, ".attachment.embedded"
  end

  test "should not convert documents with no inline attachments" do
    text = "#Heading\n\nText about my [InlineAttachment:2]."
    document = build(:published_detailed_guide, body: text)
    html = govspeak_edition_to_html(document)
    refute_select_within_html html, ".attachment.inline"
  end

  test "should convert multiple block attachments" do
    text = "#heading\n\n!@1\n\n!@2"
    attachment_1 = create(:attachment)
    attachment_2 = create(:attachment)
    document = build(:published_detailed_guide, :with_attachment, body: text, attachments: [attachment_1, attachment_2])
    html = govspeak_edition_to_html(document)
    assert_select_within_html html, "#attachment_#{attachment_1.id}"
    assert_select_within_html html, "#attachment_#{attachment_2.id}"
  end

  test "should convert multiple inline attachments" do
    text = "#Heading\n\nText about my [InlineAttachment:2] and [InlineAttachment:1]."
    attachment_1 = create(:attachment)
    attachment_2 = create(:attachment)
    document = build(:published_detailed_guide, :with_attachment, body: text, attachments: [attachment_1, attachment_2])
    html = govspeak_edition_to_html(document)
    assert_select_within_html html, "#attachment_#{attachment_1.id}"
    assert_select_within_html html, "#attachment_#{attachment_2.id}"
  end

  test "should not escape embedded attachment when attachment embed code only separated by one newline from a previous paragraph" do
    text = "para\n!@1"
    document = build(:published_detailed_guide, :with_attachment, body: text)
    html = govspeak_edition_to_html(document)
    refute html.include?("&lt;div"), "should not escape embedded attachment"
    assert_select_within_html html, ".attachment.embedded"
  end

  test "should identify internal admin links" do
    assert is_internal_admin_link?( [Whitehall.router_prefix, "admin", "test"].join("/") )
    refute is_internal_admin_link?( 'http://www.google.com/' )
    refute is_internal_admin_link?( nil )
  end

  test "prefixes embedded image urls with asset host if present" do
    Whitehall.stubs(:asset_host).returns("https://some.cdn.com")
    edition = build(:published_news_article, body: "!!1")
    edition.stubs(:images).returns([OpenStruct.new(alt_text: "My Alt", url: "/image.jpg")])
    html = govspeak_edition_to_html(edition)
    assert_select_within_html html, ".govspeak figure.image.embedded img[src=https://some.cdn.com/image.jpg]"
  end

  test "does not prefix embedded attachment urls with asset host so that access to them can be authenticated when previewing draft documents" do
    Whitehall.stubs(:asset_host).returns("https://some.cdn.com")
    edition = build(:published_publication, :with_attachment, body: "!@1")
    html = govspeak_edition_to_html(edition)
    assert_select_within_html html, ".govspeak .attachment.embedded a[href^='/'][href$='greenpaper.pdf']"
  end

  test "should remove extra quotes from blockquote text" do
    remover = stub("remover");
    remover.expects(:remove).returns("remover return value")
    Whitehall::ExtraQuoteRemover.stubs(:new).returns(remover)
    edition = build(:published_publication, body: %{He said:\n> "I'm not sure what you mean!"\nOr so we thought.})
    assert_match /remover return value/, govspeak_edition_to_html(edition)
  end

  test "should add class to last paragraph of blockquote" do
    input = "\n> firstline\n>\n> lastline\n"
    output = '<div class="govspeak"> <blockquote> <p>firstline</p> <p class="last-child">lastline</p> </blockquote></div>'
    assert_equal output, govspeak_to_html(input).gsub(/\s+/, ' ')
  end

  test "should add numbers to defined heading level" do
    input = "# first\n\n# second"
    output = '<div class="govspeak"><h1 id="first"> <span class="number">1. </span>first</h1> <h1 id="second"> <span class="number">2. </span>second</h1></div>'
    assert_equal output, govspeak_to_html(input, [], numbered_heading_level: ['h1']).gsub(/\s+/, ' ')
  end

  test "should add numbers to two defined heading levels" do
    input = "# first\n\n## first point one\n\n## first point two\n\n# second"
    expected_output_1 = '<h1 id="first"> <span class="number">1. </span>first</h1>'
    expected_output_1_1 = '<h2 id="first-point-one"> <span class="number">1.1 </span>first point one</h2>'
    expected_output_1_2 = '<h2 id="first-point-two"> <span class="number">1.2 </span>first point two</h2>'
    expected_output_2 = '<h1 id="second"> <span class="number">2. </span>second</h1>'
    actual_output = govspeak_to_html(input, [], numbered_heading_level: ['h1', 'h2']).gsub(/\s+/, ' ')
    assert_match %r(#{expected_output_1}), actual_output
    assert_match %r(#{expected_output_1_1}), actual_output
    assert_match %r(#{expected_output_1_2}), actual_output
    assert_match %r(#{expected_output_2}), actual_output
  end

  test "should not add numbers to heading before first major heading" do
    input = "## zero point one\n\n# first"
    expected_output_0 = '<h2 id="zero-point-one">zero point one</h2>'
    expected_output_1 = '<h1 id="first"> <span class="number">1. </span>first</h1>'
    actual_output = govspeak_to_html(input, [], numbered_heading_level: ['h1', 'h2']).gsub(/\s+/, ' ')
    assert_match %r(#{expected_output_0}), actual_output
    assert_match %r(#{expected_output_1}), actual_output
  end

  test "should not corrupt character encoding of numbered headings" do
    input = '# café'
    actual_output = govspeak_to_html(input, [], numbered_heading_level: ['h1'])
    assert actual_output.include?('café</h1>')
  end

  test 'converts [Contact:<id>] into a rendering of contacts/_contact for the Contact with id = <id>' do
    contact = build(:contact)
    Contact.stubs(:find_by_id).with('1').returns(contact)
    input = '[Contact:1]'
    output = govspeak_to_html(input)
    contact_html = render('contacts/contact', contact: contact)
    assert_equal "<div class=\"govspeak\">#{contact_html}</div>", output
  end

  test 'silently converts [Contact:<id>] into nothing if there is no Contact with id = <id>' do
    Contact.stubs(:find_by_id).with('1').returns(nil)
    input = '[Contact:1]'
    output = govspeak_to_html(input)
    assert_equal "<div class=\"govspeak\"></div>", output
  end

  test 'can collect all the embedded contacts into a list of Contacts in order' do
    contact_1 = build(:contact)
    contact_2 = build(:contact)
    Contact.stubs(:find_by_id).with('1').returns(contact_1)
    Contact.stubs(:find_by_id).with('2').returns(contact_2)
    input = 'We have an office at [Contact:2] but deliveries go to [Contact:1]'
    embedded_contacts = govspeak_embedded_contacts(input)
    assert_equal [contact_2, contact_1], embedded_contacts
  end

  test 'will not remove duplicate contacts' do
    contact_1 = build(:contact)
    Contact.stubs(:find_by_id).with('1').returns(contact_1)
    input = 'Our office at [Contact:1] is brilliant, you should come for a cup of tea. Remeber the address is [Contact:1]'
    embedded_contacts = govspeak_embedded_contacts(input)
    assert_equal [contact_1, contact_1], embedded_contacts
  end

  test 'will silently remove contact references that do not resolve to a Contact' do
    Contact.stubs(:find_by_id).with('1').returns(nil)
    input = 'Our office used to be at [Contact:1] but we moved'
    embedded_contacts = govspeak_embedded_contacts(input)
    assert_equal [], embedded_contacts
  end

  private

  def internal_preview_host
    "whitehall.preview.alphagov.co.uk"
  end

  def public_preview_host
    "www.preview.alphagov.co.uk"
  end

  def internal_production_host
    "whitehall.production.alphagov.co.uk"
  end

  def public_production_host
    "www.gov.uk"
  end
end
