module safepine_core.pipelines.yahoo;

import std.net.curl;
import std.csv: csvReader;
import std.datetime;
import std.file;
import std.conv;
import std.algorithm;
import std.json;

enum output {frame, csv}
enum logger {on, off}
enum intervals {daily = "1d", weekly = "1wk", monthly = "1mo"}

struct Frame
{
  string name;
  Price price;
  Dividend div;
  Split split;
  Date date;
}

struct Price
{
  double adjclose;
  double close;
  double high;
  double low;
  double open;
  long volume;
}

struct Dividend
{
  double amount;
} 

struct Split
{
  long denominator;
  long numerator;
}

// CSV Readers
struct Price_csvReader
{
  string date;
  string open;
  string high;
  string low;
  string close;
  string adjclose;
  string volume;
}

struct Split_csvReader
{
  string date;
  string split;
}

struct Dividend_csvReader
{
  string date;
  string amount;
}

Frame[][] NormalizeFrameDates(Frame[] benchmark, Frame[][] lists)
{
  Frame[][] result;
  Frame[] element = lists[0];
  bool[] doesDateExistsForAll;
  bool addDate;
  Date[] normalized_dates;

  // Get all dates in benchmark
  // Find all common dates in lists
  for(int i = 0; i < benchmark.length; ++i)
  {
    addDate = true;
    for(int n = 0; n < lists.length; ++n) doesDateExistsForAll ~= false;
    for(int j = 0; j < lists.length; ++j)
    {
      for(int k = 0; k < lists[j].length; ++k)
      {
        if(benchmark[i].date == lists[j][k].date)
          doesDateExistsForAll[j] = true;
      }
    }
    for(int n = 0; n < lists.length; ++n)
    {
      if(doesDateExistsForAll[n] == false) addDate = false;
    }
    if(addDate)
    {
      normalized_dates ~= benchmark[i].date;
    }
  }

  // Add benchmark's normalized frames to result
  Frame[] normalized_benchmark;
  int i_n = 0;
  for(int i = 0; i < benchmark.length; ++i)
  {
    if(normalized_dates[i_n] == benchmark[i].date)
    {
      normalized_benchmark ~= benchmark[i];
      i_n += 1;
    }
  }
  result ~= normalized_benchmark;

  // Add normalized frames of lists to result
  for(int k = 0; k < lists.length; ++k)
  {
    Frame[] normalized_list_item;
    i_n = 0;

    for(int i = 0; i < lists[k].length; ++i)
    {
      if(i_n < normalized_dates.length)
      {
        if(normalized_dates[i_n] <= lists[k][i].date)
        {
          normalized_list_item ~= lists[k][i];
          i_n += 1;
        } 
      }
    }
    result ~= normalized_list_item;
  }

  return result;
}

void PrintFrame(Frame[] frame_IN)
{
  import std.stdio: writeln;

  // Weird break
  writeln();
  writeln("-----::-----::-----::-----::");
  writeln("-----::-----::-----::-----::");
  writeln("Length of " ~ frame_IN[0].name ~ " is " ~  to!string(frame_IN.length));
  writeln("Open, high, low, close, volume");
  for(int j = 0; j < frame_IN.length; ++j)
  {
    writeln(to!string(frame_IN[j].date) ~ ": "~ to!string(frame_IN[j].price.open) ~ ", ", to!string(frame_IN[j].price.high) ~ ", " ~to!string(frame_IN[j].price.low) ~ ", " ~ to!string(frame_IN[j].price.close) ~ ", " ~ to!string(frame_IN[j].price.volume));
  }
}

struct Yahoo
{
public:
  // Write template
  T Write(output val = output.frame, logger log = logger.on, T = bool)(string option = "")
  {
    T result = WriteImpl!val(option);
    if(log == logger.on) WriteLogger!val;
    return result;
  }

  // Write implementation - frame
  Frame[] WriteImpl(output val, T = Frame[])(string option = "")
    if(val == output.frame)
  {
    Frame[] result;
    if(_miningDone) 
    {
      Split s;
      Dividend d;
      d.amount = 0;

      for (int i = 0; i<to!int(_j["prices"].array.length); ++i)
      {
        Frame frame;
        frame.name = to!string(_j["name"]); 
        string date = to!string(_j["prices"][i]["date"]);
        int year = to!int(date[1 .. 5]);
        int month = to!int(date[6 .. 8]);
        int day = to!int(date[9 .. 11]);
        frame.date = Date(year, month, day);

        if("denominator" in _j["prices"][i])
        {
          s.denominator = _j["prices"][i]["denominator"].integer;
          s.numerator = _j["prices"][i]["numerator"].integer;
          _splitsWritten++;    
        }
        else if ("amount" in _j["prices"][i])
        {
          string amount_s = _j["prices"][i]["amount"].str;
          amount_s = amount_s[1 .. amount_s.length-1];
          d.amount = to!double(amount_s);
          _divsWritten++;
        }
        else
        {
          // Make sure to save div/split with the correct price/date data. 
          frame.div = d;
          frame.split = s;

          d.amount = 0;
          s.denominator = 0;
          s.numerator = 0;

          Price price;
          price.adjclose = to!double(_j["prices"][i]["adjclose"].str);
          price.close = to!double(_j["prices"][i]["close"].str);
          price.high = to!double(_j["prices"][i]["high"].str);
          price.low = to!double(_j["prices"][i]["low"].str);
          price.open = to!double(_j["prices"][i]["open"].str);
          price.volume = to!long(_j["prices"][i]["volume"].str);

          frame.price = price;
          _pricesWritten++;
          result ~= frame;
        }
      }
    }
    return result;
  } 

  // Write implementation - frame
  void WriteLogger(output val)()
    if(val == output.frame)
  {
    import std.stdio: writeln;

    if(_miningDone) 
    {   
      writeln("Frame generated for "~_name~" with "~to!string(_divsWritten)~ " dividends, " ~to!string(_splitsWritten)~ " splits and "~to!string(_pricesWritten)~ " prices.");
    }
  } 

  // Write implementation - csv
  // Name, Date, Unadjusted Open, Unadjusted High, Unadjusted Low, Unadjusted Close, Unadjusted Volume, Dividends, Splits, Adjusted Open, Adjusted High, Adjusted Low, Adjusted Close, Adjusted Volume  
  string WriteImpl(output val, T = string)(string option = "")
    if(val == output.csv)
  { 
    string result = "";
    Frame[] data_frame = Write!(output.frame, logger.off, Frame[]); 
    for(int i = 0; i<data_frame.length; i++)
    {
      result~=_name~",";

      // converts yyyymmdd to yyyy-mm-dd
      string date_conversion = data_frame[i].date.toISOString();
      date_conversion = date_conversion[0 .. 4]~"-"~date_conversion[4 .. 6]~"-"~date_conversion[6 .. 8];

      result~=to!string(date_conversion)~",";
      result~=to!string(data_frame[i].price.open)~",";
      result~=to!string(data_frame[i].price.high)~",";
      result~=to!string(data_frame[i].price.low)~",";
      result~=to!string(data_frame[i].price.close)~",";
      result~=to!string(data_frame[i].price.volume)~",";
      result~=to!string(data_frame[i].div.amount)~",";
      if(data_frame[i].split.numerator != 0 && data_frame[i].split.denominator != 0)
      {
        result~=to!string(data_frame[i].split.numerator/data_frame[i].split.denominator)~",";
      }
      else
      {
        result~=to!string("1.0"~",");
      }
      result~="0.0"~","; // Adjusted open n.a. in yahoo finance
      result~="0.0"~","; // Adjusted high n.a. in yahoo finance
      result~="0.0"~","; // Adjusted low n.a. in yahoo finance
      result~=to!string(data_frame[i].price.adjclose)~","; 
      result~="0.0"; // Adjusted volume n.a. in yahoo finance
      result~="\n";
    }   
    return result;
  }

  // Write implementation - csv
  void WriteLogger(output val)()
    if(val == output.csv)
  {
    import std.stdio: writeln;
    writeln("CSV writer executed.");
  }   

  // Mine template
  void Mine(logger log = logger.on)(Date begin, Date end, string name, intervals interval=intervals.daily)
  {
    MineImpl(begin, end, name, interval);
    if(log == logger.on) MineLogger();
  }

  // Mine implementation
  void MineImpl(Date begin, Date end, string name, intervals interval)
  {
    // Copy begin/end dates and stock name to private
    _beginDate = begin;
    _endDate = end;
    _name = name;
    _miningDone = false;

    // Generate unix times and date times
    auto est = new immutable SimpleTimeZone(hours(-7));
    _beginDate_s = to!string(_beginDate);
    _endDate_s = to!string(_endDate);
    _beginUnix_s = to!string( SysTime(_beginDate, est).toUnixTime() );
    _endUnix_s = to!string( SysTime(_endDate, est).toUnixTime() );

    // Reset counters
    _divsWritten = 0; 
    _splitsWritten = 0;
    _pricesWritten = 0; 

    string cachePath = "cache/";
    if (exists(cachePath~_name~"_"~_beginDate_s~"_"~_endDate_s~"_prices_cache.json"))
    {
      _miningDone = true;
      string raw = to!string(read(cachePath~_name~"_"~_beginDate_s~"_"~_endDate_s~"_prices_cache.json"));
      _j = parseJSON(raw);
      return;
    }

    // Curl it
    try
    {
      // Assemble query. Use unix time.
      _query = "https://query1.finance.yahoo.com/v7/finance/download/"~_name~"?period1="~_beginUnix_s~"&period2="~_endUnix_s~"&interval="~interval~"&events=history&includeAdjustedClose=true";
      string shadow_content = to!string( get(_query));
      auto prices = shadow_content.csvReader!Price_csvReader(',');

      _query = "https://query1.finance.yahoo.com/v7/finance/download/"~_name~"?period1="~_beginUnix_s~"&period2="~_endUnix_s~"&interval="~interval~"&events=splits&includeAdjustedClose=true";
      shadow_content = to!string( get(_query));
      auto splits = shadow_content.csvReader!Split_csvReader(',');

      _query = "https://query1.finance.yahoo.com/v7/finance/download/"~_name~"?period1="~_beginUnix_s~"&period2="~_endUnix_s~"&interval="~interval~"&events=divs&includeAdjustedClose=true";
      shadow_content = to!string( get(_query));
      auto dividends = shadow_content.csvReader!Dividend_csvReader(',');

      _j = [ "prices": "" ];
      _j["name"] = _name;

      int price_index = 0;
      foreach (price; prices) 
      {
        JSONValue price_json;
        price_json["date"] = JSONValue(price.date);
        price_json["adjclose"] = JSONValue(price.adjclose);
        price_json["close"] = JSONValue(price.close);
        price_json["high"] = JSONValue(price.high);
        price_json["low"] = JSONValue(price.low);
        price_json["open"] = JSONValue(price.open);
        price_json["volume"] = JSONValue(price.volume);
        if(price_index == 1)
          _j["prices"] = JSONValue( [price_json] );
        else if(price_index > 1) 
          _j["prices"].array ~= price_json;
        price_index += 1;
      }

      Dividend_csvReader[] dividend_array;
      foreach (dividend; dividends) 
        dividend_array ~= dividend; 
      dividend_array = dividend_array[1 .. dividend_array.length];

      Split_csvReader[] split_array;
      foreach (split; splits) 
        split_array ~= split;
      split_array = split_array[1 .. split_array.length];

      int split_index = 0;
      int dividend_index = 0;
      for(int i = 0; i<_j["prices"].array.length; ++i)
      {
        string date = to!string(_j["prices"][i]["date"]);
        int year = to!int(date[1 .. 5]);
        int month = to!int(date[6 .. 8]);
        int day = to!int(date[9 .. 11]);
        Date date_prices = Date(year, month, day);

        if(dividend_array.length > 0 && dividend_index<dividend_array.length)
        {
          date = dividend_array[dividend_index].date;
          year = to!int(date[0 .. 4]);
          month = to!int(date[5 .. 7]);
          day = to!int(date[8 .. 10]);
          Date date_dividend = Date(year, month, day);
          if(date_prices >= date_dividend)
          {
            if(dividend_index<dividend_array.length)
            {
              _j["prices"][i]["amount"] = JSONValue(dividend_array[dividend_index].amount);
              dividend_index += 1;         
            }
          }
        }

        if(split_array.length > 0 && split_index<split_array.length)
        {
          date = split_array[split_index].date;
          year = to!int(date[0 .. 4]);
          month = to!int(date[5 .. 7]);
          day = to!int(date[8 .. 10]);
          Date date_splits = Date(year, month, day);
          if(date_prices >= date_splits)
          {
            if(split_index<split_array.length)
            {
              _j["prices"][i]["denominator"] = to!int(split_array[split_index].split[0])-48;
              _j["prices"][i]["numerator"] = to!int(split_array[split_index].split[2])-48;
              split_index += 1;       
            }
          }
        }
      }

      // Cache it!
      if (!exists(cachePath))
        mkdir(cachePath);
      std.file.write(cachePath~_name~"_"~_beginDate_s~"_"~_endDate_s~"_prices_cache.json", _j.toPrettyString);

      _miningDone = true;
    }
    catch (CurlException e)
    {
      _exceptions[_exceptionIndex] = e.msg;
      _exceptionIndex++;
      _miningDone = false;
    }
  }

  // Mine logger
  void MineLogger()
  {
    import std.stdio: writeln;

    writeln("Retrieveing "~_name~" between "~_beginUnix_s~" and "~_endUnix_s~".");
    writeln("Using query: "~_query);

    if(_lastExceptionIndex != _exceptionIndex)
    {
      for(int i = _lastExceptionIndex; i<_exceptionIndex; i++)
      {
        writeln(_exceptions[_lastExceptionIndex]);
      }
      _lastExceptionIndex = _exceptionIndex;
    }
  }

  int PriceLength()
  {
    if(_miningDone) return to!int(_j["prices"].array.length);
    else return -1; 
  }

private:
  string _name; // name of the currently mined stock
  string _query; // url query for the stock

  Date _beginDate; // begin date in date.time
  Date _endDate; // end daye in date.time
  string _beginDate_s; // begin date as string
  string _endDate_s; // end date as string
  string _beginUnix_s; // begin date in unix time. needed to bind to yahoo url
  string _endUnix_s;  // end date in unix time. needed to bind to yahoo url

  bool _miningDone; // detecs if mining is completed
  JSONValue _j; // json collected from yahoo after mining is done

  const int MAXEXCEPTIONS = 100; // maximum allowed number of exceptions
  string[MAXEXCEPTIONS] _exceptions; // exception container.
  int _exceptionIndex = 0; // current exception index.
  int _lastExceptionIndex = 0; // to print exceptions

  int _divsWritten; // number of data frame divs
  int _splitsWritten; // number of data frame splits
  int _pricesWritten; // number of data frame prices
}