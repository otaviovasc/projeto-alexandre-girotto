class SetCabanaGuideLinks < ActiveRecord::Migration[7.0]
  GUIDE_LINKS = {
    'collina' => 'https://drive.google.com/file/d/1g7417KQ6AxjA66nknhvRF7E-ZPlnLD8-/view?usp=sharing',
    'vecchio toro' => 'https://drive.google.com/file/d/1wdhdV0ThNI9Vh0SZD21HwsNMtEKMWZ7L/view?usp=sharing',
    'zucchero' => 'https://drive.google.com/file/d/1DHc1AWNxfc2S-zQJlD7bNcQdMDZ6-nhJ/view?usp=sharing',
    'nuvolo' => 'https://drive.google.com/file/d/1WYufjWpwAm2VJ5Ii1uICmXqnNTJO4q99/view?usp=sharing',
    'vita' => 'https://drive.google.com/file/d/1vl7N00BGQB9kNVYTlLoK0j_yV6F_MJXy/view?usp=sharing',
    'valle' => 'https://drive.google.com/file/d/1kaXDz8JVsg8D-hJLMxYo9pQXbJmMmvs3/view?usp=sharing'
  }.freeze

  class CabanaRecord < ActiveRecord::Base
    self.table_name = 'cabanas'
  end

  def up
    GUIDE_LINKS.each do |name, link|
      CabanaRecord.where('LOWER(name) LIKE ?', "#{name}%").update_all(link_guia: link)
    end
  end

  def down
    GUIDE_LINKS.each do |name, link|
      CabanaRecord.where('LOWER(name) LIKE ?', "#{name}%")
                   .where(link_guia: link)
                   .update_all(link_guia: nil)
    end
  end
end
