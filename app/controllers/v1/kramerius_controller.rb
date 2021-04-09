class V1::KrameriusController < V1::V1Controller
  require 'open-uri'
  # require 'json'

  def citation
    code = params[:code]
    uuid = params[:uuid] 
    lang = params[:lang] || "cs" 
    base_url = params[:url]
    base_url = "https://kramerius.mzk.cz" if base_url == "https://kramerius-vs.mzk.cz" || base_url == "https://dnnt.mzk.cz"
    base_url = "https://kramerius5.nkp.cz" if base_url == "https://kramerius-vs.nkp.cz" || base_url == "https://kramerius-dnnt.nkp.cz" || base_url == "https://ndk.cz"
    f = params[:format] || "txt"
    if code.nil? && base_url.nil?
      render status: 422, plain: "Missing code or url parameter" and return
    end
    if uuid.nil?
      render status: 422, plain: "Missing uuid parameter" and return
    end
    base_url = get_base_url code if base_url.nil?
    if base_url.nil?
      render status: 404, plain: "Not Found" and return
    end
    begin
      citation = build_citation(base_url, uuid, f, lang)
      render status: 200, plain: citation
    rescue OpenURI::HTTPError => e
      if e.to_s.strip == "404"
        render status: 404, plain: "Not Found"
      else
        render status: 422, plain: "HTTP Error"
      end
    end 
  end


  # def test
  #   mods = xml("http://localhost:8080/mods.xml")
  #   render status: 200, plain: "#{authors(mods)}"
  # end    

  private

    def build_citation(base, uuid, f, lang)
      root_item =  item(base, uuid)     
      model = root_item["model"]
      page_number = root_item["details"]["pagenumber"] if model == "page" && root_item["details"]
      context = root_item["context"][0]
      root = context[0]
      root_uuid = root["pid"]
      root_model= root["model"]
      root_mods = mods(base, root_uuid)
      periodical_volume = nil
      periodical_issue = nil
      monograph_unit_mods = nil
      article_mods = nil
      issue_mods = nil
      context[1..-1].each do |doc|
        if doc["model"] == "periodicalvolume"
          periodical_volume = item(base, doc["pid"])
        elsif doc["model"] == "periodicalitem"
          periodical_issue = item(base, doc["pid"])
          issue_mods = mods(base, doc["pid"])
        elsif doc["model"] == "supplement"
          if periodical_issue.nil?
            periodical_issue = item(base, doc["pid"])
            issue_mods = mods(base, doc["pid"])
          end
        elsif doc["model"] == "monographunit"
          monograph_unit_mods = mods(base, doc["pid"])
        elsif doc["model"] == "article"
          article_mods = mods(base, doc["pid"])
        end
      end
      citation = ""
      monograph_unit_number = nil
      if root_model != "periodical"
        if monograph_unit_mods
          authors = authors(monograph_unit_mods)
          monograph_unit_number = unit_number(monograph_unit_mods) 
          unless authors.blank?
            citation += authors
          else
            citation += authors(root_mods)
          end
        else
          citation += authors(root_mods)
        end
      end 

      unless article_mods.blank?
        citation += authors(article_mods)
        citation += title(article_mods, "txt")
      end

      citation += title(root_mods, f)

      if root_model == "map"
        scale = mods_element(root_mods, "//subject/cartographics/scale") 
        scale = (scale || "").strip
        if scale.blank?
          scale = "Měřítko neuvedeno"
        else
          scale = scale[8, scale.length] if scale.downcase.start_with? "měřítko"
        end
        citation += "#{scale}. "
      end

      if periodical_volume.nil? && periodical_issue.nil?
        if monograph_unit_mods
          pub = publisher(monograph_unit_mods)
          pub.blank? ? citation += publisher(root_mods) : citation += pub
        else
          citation += publisher(root_mods)
        end
      else
        publisher = publisher_place_and_name(root_mods)
        citation += volume_and_issue(publisher, periodical_volume, periodical_issue, issue_mods, article_mods, f)
      end

      unless monograph_unit_number.blank?
        p = lang == "cs" ? "sv." : "sv."
        citation += "#{p} #{monograph_unit_number}. "
      end

      if root_model == "map"
        extent = mods_element(root_mods, "//physicalDescription/extent") 
        citation += "#{extent.strip}. " unless extent.blank?
      end

      unless page_number.blank?
        page_number = page_number.strip.gsub("\u00A0", "")
        p = lang == "cs" ? "s" : "p"
        citation = citation[0..(citation.length - 3)] + ", " if citation.end_with? ". "
        citation += "#{p}. #{page_number}. "
      end
      citation += doi(article_mods, f) unless article_mods.blank?
      citation += isbn(root_mods) + issn(root_mods)
      citation.strip!
      Log.create(kramerius: base, uuid: uuid, model: model, root_model: root_model, citation: citation, format: f, timestamp: Time.now)
      return citation
    end


    def volume_and_issue(publisher, volume, issue, issue_mods, article_mods, f)
      volume_number = volume["details"]["volumeNumber"] if volume && volume["details"]
      volume_year = volume["details"]["year"] if volume && volume["details"]
      issue_number = issue["details"]["issueNumber"] if issue && issue["details"]
      issue_part = issue["details"]["partNumber"] if issue && issue["details"]
      issue_date = issue["details"]["date"] if issue && issue["details"]
      issue_number = issue_part if issue_number.blank?
      issue_number = mods_element(issue_mods, "//titleInfo/partNumber") if issue_number.blank? && !issue_mods.blank?
      if !issue_date.blank?
        publisher += ", " unless publisher.blank?
        publisher += issue_date
      elsif !volume_year.blank?
        publisher += ", " unless publisher.blank?
        publisher += volume_year
      end
      unless volume_number.blank?
        publisher += ", " unless publisher.blank?
        publisher += f == "html" ? "<b>#{volume_number}</b>" : "#{volume_number}"
      end
      unless issue_number.blank? && issue_mods.blank?
        issue = ""
        issue += issue_number unless issue_number.blank?
        unless issue_mods.blank?
          edition = edition(issue_mods)
          unless edition.blank?
            issue += ", " unless issue.blank?
            issue += edition unless issue.blank?
          end
        end
        publisher += "(#{issue})"
      end
      publisher.strip!
      unless article_mods.blank?
        extent = article_extent(article_mods)
        publisher += ", #{extent}" unless extent.blank?
      end
      return publisher.blank? ? "" : publisher + ". "
    end


    def json(url)
      JSON.load(open(url))
    end

    def item_url(base, uuid)
      "#{base}/search/api/v5.0/item/#{uuid}"
    end

    def mods_url(base, uuid)
      "#{item_url(base, uuid)}/streams/BIBLIO_MODS"
    end

    def xml(url) 
      doc = Nokogiri::XML(open(url))
      doc.remove_namespaces!
      doc.xpath('modsCollection/mods').first
    end

    def mods(base, uuid)
      xml(mods_url(base, uuid))
    end
    
    def item(base, uuid)
      json(item_url(base, uuid))
    end


    def authors(mods)
      list = []
      mods.xpath('name').each do |name|
        family = first_content(name, 'namePart[@type="family"]')
        given = first_content(name, 'namePart[@type="given"]')
        name = first_content(name, 'namePart[not(@type)]')
        if !family.blank? || !given.blank? 
          author_to_list(list, family, given)
        elsif !name.blank?
          name.strip!
          name = name[0...-1] if name[-1] == ","
          splits = name.split(",")
          if splits.size == 2 && !name.index("(")
            family = splits[0]
            given = splits[1].strip
            author_to_list(list, family, given)
          else
            author_to_list(list, nil, name)
          end
        end
      end
      if list.empty? 
        ""
      elsif list.size > 4
        "#{list[0]} et al. "
      elsif list.size == 1
        "#{list[0]}. "
      else
        "#{list[0...-1].join(", ")} a #{list[-1]}. "
      end
    end


    def author_to_list(list, family, given)
      list << author(family, given, list.empty?)
    end

    def author(family, given, reverse = true)
      name = ""
      if !family.blank?
        family = family.mb_chars.upcase
        unless given.blank?
          name = reverse ? "#{family}, #{given}" : "#{given} #{family}"
        end
      else
        name = given
      end
      name
    end

    def unit_number(mods)
      list = mods.xpath("titleInfo")
      return "" if list.empty?
      return first_content(list[0], "partNumber")
    end

    def title(mods, f)
      list = mods.xpath("titleInfo")
      return "" if list.empty?
      titleInfo = list[0]
      title = first_content(titleInfo, "title")
      nonSort = first_content(titleInfo, "nonSort")
      subTitle = first_content(titleInfo, "subTitle")
      partNumber = first_content(titleInfo, "partNumber")
      partName = first_content(titleInfo, "partName")
      result = title
      result = "#{nonSort} #{title}" unless nonSort.blank?
      result += ": #{subTitle}" unless subTitle.blank?
      result += ", #{partNumber}" unless partNumber.blank?
      result += ": #{partName}" unless partName.blank?
      return "" if result.blank?
      return f == "html" ? "<i>#{result}</i>. " : "#{result}. "
    end


    def edition(mods)
      mods.xpath("//note").each do |n|
        note = n.text.strip.downcase
        return "ranní vydání" if note.index "ranní vydání;"
        return "odpolední vydání" if note.index "odpolední vydání;"
        return "polední vydání" if note.index "polední vydání;"
        return "večerní vydání" if note.index "večerní vydání;"
      end
      return ""
    end

    def mods_element(mods, xpath)
      mods.xpath(xpath).each do |n|
        return n.text.strip || ""
      end
      return ""
    end

    def article_extent(mods)
      extents = mods.xpath("//part/extent")
      if extents.empty?
        return ""
      end
      extent = extents[0]
      ext_start = first_content(extent, 'start')
      ext_end = first_content(extent, 'end')
      ext_list = first_content(extent, 'list')
      if !ext_start.blank? && !ext_end.blank?
        if ext_start == ext_end
          return ext_start
        else
          return "#{ext_start}-#{ext_end}"
        end
      elsif !ext_list.blank?
        if ext_list.index("-").nil? || ext_list.split("-")[0] != ext_list.split("-")[1]
          return ext_list
        else
          return ext_list.split("-")[0]
        end
      end



      return ""
    end

    def publisher_place_and_name(mods)
      result = ""
      place = trim(first_content(mods, "originInfo/place/placeTerm[@type='text' and not(@authority='marccountry')]"), ":")
      publisher = trim(first_content(mods, "originInfo/publisher"), ",")
      result = place unless place.blank?
      unless publisher.blank?
        result += result.blank? ? publisher : ": #{publisher}"
      end
      return result.blank? ? "" : "#{result}"
    end

    def publisher(mods)
      result = publisher_place_and_name(mods)
      date_from = first_content(mods, 'originInfo/dateIssued[@point="start"]')
      date_to = first_content(mods, 'originInfo/dateIssued[@point="end"]')
      date = first_content(mods, 'originInfo/dateIssued[not(@type)]')
      if !date_from.blank? && !date_to.blank?
        date = "#{date_from}-#{date_to}"
      elsif  !date_from.blank?
        date = date_from
      elsif  !date_to.blank?
        date = date_to
      end
      unless date.blank?
        if date.end_with?("-9999") || date.end_with?("-uuuu")
          date = date[0...-4]
        end
        result += result.blank? ? date : ", #{date}"
      end
      return result.blank? ? "" : "#{result}. "
    end

    def isbn(mods)
      isbn = first_content(mods, 'identifier[@type="isbn"]')
      return isbn.blank? ? "" : "ISBN #{isbn}. "
    end

    def issn(mods)
      issn = first_content(mods, 'identifier[@type="issn"]')
      return issn.blank? ? "" : "ISSN #{issn}. "
    end

    def doi(mods, f)
      doi = first_content(mods, 'identifier[@type="doi"]')
      return "" if doi.blank? 
      if !doi.downcase.start_with?("http")
        doi = 'https://doi.org/' + doi
      end
      if f == "html" 
        doi = "<a href=\"#{doi}\" target=\"_blank\">#{doi}</a>"
      end
      return "DOI: #{doi}. "
    end


    def first_content(element, xpath)
      first = element.xpath(xpath).first
      first ? first.text.strip : ""
    end

    def trim(text, char)
      return "" if text.blank?
      result = text.strip
      result = result[0...-1] if result[-1] == char
      return result.strip
    end

    def get_base_url(code)
      case code
      when "mzk"
        "https://kramerius.mzk.cz"
      when "nkp"
        "http://kramerius5.nkp.cz"
      when "vkol"
        "http://kramerius.kr-olomoucky.cz"
      when "knav"
        "https://kramerius.lib.cas.cz"
      end
    end



end
