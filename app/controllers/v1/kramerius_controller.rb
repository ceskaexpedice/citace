class V1::KrameriusController < V1::V1Controller

  require 'open-uri'

  def citation
    code = params[:code]
    uuid = params[:uuid]    
    if code.nil?
      render status: 422, plain: "Missing code parameter" and return
    end
    if uuid.nil?
      render status: 422, plain: "Missing uuid parameter" and return
    end
    base_url = get_base_url code
    if base_url.nil?
      render status: 404, plain: "Not Found" and return
    end
    mods_url = "#{base_url}/search/api/v5.0/item/#{uuid}/streams/BIBLIO_MODS"
    citation = build_citation(mods_url)
    render status: 200, plain: "#{citation}"
  end


  def test
    citation = build_citation("http://localhost:8080/mods.xml")
    render status: 200, plain: "#{citation}"
  end    

  private

    def build_citation(mods_url)
      doc = Nokogiri::XML(open(mods_url))
      doc.remove_namespaces!
      mods = doc.xpath('modsCollection/mods')
      authors(mods) + title(mods)
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

    def title(mods)
      list = mods.xpath("titleInfo")
      return "" if list.empty?
      titleInfo = list[0]
      title = titleInfo.xpath("title").text
      nonSort = titleInfo.xpath("nonSort").text
      subTitle = titleInfo.xpath("subTitle").text
      partNumber = titleInfo.xpath("partNumber").text
      partName = titleInfo.xpath("partName").text
      result = title
      result = "#{nonSort} #{title}" unless nonSort.blank?
      result += ": #{subTitle}" unless subTitle.blank?
      result += ", #{partNumber}" unless partNumber.blank?
      result += ": #{partName}" unless partName.blank?
      result
    end


    def first_content(element, xpath)
      first = element.xpath(xpath).first
      first ? first.text : nil
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
