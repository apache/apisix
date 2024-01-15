/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.apache.dubbo.backend;

import java.util.HashMap;
import java.util.Map;

public class PoJo {
    private String aString;

    private Boolean aBoolean;
    private Byte aByte;
    private Character acharacter;
    private Integer aInt;

    private Float aFloat;
    private Double aDouble;
    private Long aLong;
    private Short aShort;

    private String[] strings;

    private Map<String, String> stringMap;

    public String getaString() {
        return aString;
    }

    public void setaString(String aString) {
        this.aString = aString;
    }

    public Boolean getaBoolean() {
        return aBoolean;
    }

    public void setaBoolean(Boolean aBoolean) {
        this.aBoolean = aBoolean;
    }

    public Byte getaByte() {
        return aByte;
    }

    public void setaByte(Byte aByte) {
        this.aByte = aByte;
    }

    public Character getAcharacter() {
        return acharacter;
    }

    public void setAcharacter(Character acharacter) {
        this.acharacter = acharacter;
    }

    public Integer getaInt() {
        return aInt;
    }

    public void setaInt(Integer aInt) {
        this.aInt = aInt;
    }

    public Float getaFloat() {
        return aFloat;
    }

    public void setaFloat(Float aFloat) {
        this.aFloat = aFloat;
    }

    public Double getaDouble() {
        return aDouble;
    }

    public void setaDouble(Double aDouble) {
        this.aDouble = aDouble;
    }

    public Long getaLong() {
        return aLong;
    }

    public void setaLong(Long aLong) {
        this.aLong = aLong;
    }

    public Short getaShort() {
        return aShort;
    }

    public void setaShort(Short aShort) {
        this.aShort = aShort;
    }



    public Map<String, String> getStringMap() {
        return stringMap;
    }

    public void setStringMap(Map<String, String> stringMap) {
        this.stringMap = stringMap;
    }

    public String[] getStrings() {
        return strings;
    }

    public void setStrings(String[] strings) {
        this.strings = strings;
    }

    public static PoJo getTestInstance(){
        PoJo poJo = new PoJo();
        poJo.aBoolean =true;
        poJo.aByte =1;
        poJo.acharacter ='a';
        poJo.aInt =2;
        poJo.aDouble = 1.1;
        poJo.aFloat =1.2f;
        poJo.aLong = 3L;
        poJo.aShort = 4;
        poJo.aString ="aa";
        HashMap<String, String> poJoMap = new HashMap<>();
        poJoMap.put("key","value");
        poJo.stringMap = poJoMap;
        poJo.strings = new String[]{"aa","bb"};
        return poJo;
    }
}
