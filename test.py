fmap = ['unused','aid','eid','gid','mylist_id','list_other_episodes','IsDeprecated','state', 'size','ed2k','md5','sha1','crc32','unused','unused','reserved', 'quality','src','audio','audio_bitrate_list','video','video_bitrate','res','file_type', 'dub','sub','length_in_seconds','description','aired_date','unused','unused','anidb_file_name', 'mylist_state','mylist_filestate','mylist_viewed','mylist_viewdate','mylist_storage','mylist_source','mylist_other','unused']

amap = ['anime_total_episodes','highest_episode_number','year','file_type','related_aid_list','related_aid_type','category_list','reserved', 'romanji_name','kanji_name','english_name','other_name','short_name_list','synonym_list','retired','retired', 'epno','ep_name','ep_romanji_name','ep_kanji_name','episode_rating','episode_vote_count','unused','unused', 'group_name','group_short_name','unused','unused','unused','unused','unused','date_aid_record_updated']

fields = ['fid', 'aid', 'eid', 'gid', 'size', 'ed2k', 'md5', 'sha1', 'crc32', 'dub', 'sub', 'src', 'audio', 'video', 'res', 'file_type', 'group_short_name', 'epno', 'ep_name', 'ep_romanji_name', 'ep_kanji_name', 'year', 'anime_total_episodes', 'romanji_name', 'english_name','kanji_name']

def make_map(a, b):
    m = ''.join(['1' if x in b else '0' for x in a])
    return '%0*X' % ((len(m) + 3) // 4, int(m, 2))
print(make_map(fmap, fields))
print(make_map(amap, fields))
