#pragma once
#include <algorithm>
#include <string>
#include <utility>
#include <vector>
namespace LexiCandidateLayout {
using Range=std::pair<int,int>;
inline bool longWord(const std::wstring& text) {
    int units=0;
    for(size_t i=0;i<text.size();++i) {
        unsigned long c=static_cast<unsigned long>(text[i]);
        units+=c<128?1:2;
        if(c>=0xd800&&c<=0xdbff&&i+1<text.size()) {
            auto next=static_cast<unsigned long>(text[i+1]);
            if(next>=0xdc00&&next<=0xdfff)++i;
        }
    }
    return units>10;
}
inline std::vector<Range> pages(const std::vector<std::wstring>& texts,int count=5) {
    std::vector<Range> result;int start=0;count=std::max(1,std::min(9,count));
    for(int i=0;i<static_cast<int>(texts.size());++i) {
        bool longText=longWord(texts[size_t(i)]);
        if(i>start&&(longText||i-start>=count)){result.emplace_back(start,i);start=i;}
        if(longText){result.emplace_back(i,i+1);start=i+1;}
    }
    if(start<static_cast<int>(texts.size()))result.emplace_back(start,int(texts.size()));
    return result;
}
inline Range range(const std::vector<Range>& list,int selected) {
    for(auto r:list)if(selected>=r.first&&selected<r.second)return r;
    return list.empty()?Range{0,0}:list.front();
}
inline int next(const std::vector<Range>& list,int selected,int direction) {
    if(list.empty())return 0;
    int index=0;
    for(size_t i=0;i<list.size();++i)if(selected>=list[i].first&&selected<list[i].second){index=int(i);break;}
    return list[size_t(std::max(0,std::min(int(list.size())-1,index+direction)))].first;
}
inline std::wstring compact(const std::wstring& full,size_t limit) {
    std::wstring result;
    for(wchar_t c:full) {
        if(c==L'\n'||c==L'\r'||c==L'\t'||c==L' ') {if(!result.empty()&&result.back()!=L' ')result+=L' ';}
        else result+=c;
    }
    if(!result.empty()&&result.back()==L' ')result.pop_back();
    if(result.size()>limit&&limit>0) {
        result.resize(limit-1);
        if(!result.empty()&&result.back()>=0xd800&&result.back()<=0xdbff)result.pop_back();
        result+=L'…';
    }
    return result;
}
}
