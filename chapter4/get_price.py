#!/usr/bin/env python3
import json
import sys

import requests
from tabulate import tabulate


def build_pricing_table(json_data, table_data):
    for item in json_data["Items"]:
        meter = item["meterName"]
        table_data.append(
            [
                item["armSkuName"],
                item["retailPrice"],
                item["currencyCode"],
                item["unitOfMeasure"],
                item["armRegionName"],
                meter,
                item["productName"],
            ]
        )


def get_user_input():
    if len(sys.argv) < 3:
        print("Usage: get_price.py <region> <sku>")
        sys.exit(1)

    selected_region = sys.argv[1]
    selected_sku = sys.argv[2]

    return selected_region, selected_sku


def main():
    selected_region, selected_sku = get_user_input()

    table_data = []
    table_header = [
        "SKU",
        "Retail Price",
        "Currency",
        "Unit",
        "Region",
        "Meter",
        "Product Name",
    ]
    table_data.append(table_header)

    api_url = (
        "https://prices.azure.com/api/retail/prices?api-version=2021-10-01-preview"
    )
    query = f"armRegionName eq '{selected_region}' and armSkuName eq '{selected_sku}' and priceType eq 'Consumption' "
    response = requests.get(api_url, params={"$filter": query})
    json_data = json.loads(response.text)
    if json_data["Items"] == []:
        print(
            f"No results found for region '{selected_region}' and sku '{selected_sku}'"
        )
        sys.exit(1)

    build_pricing_table(json_data, table_data)
    nextPage = json_data["NextPageLink"]

    while nextPage:
        response = requests.get(nextPage)
        json_data = json.loads(response.text)
        nextPage = json_data["NextPageLink"]
        build_pricing_table(json_data, table_data)

    print(tabulate(table_data, headers="firstrow", tablefmt="rounded_outline"))


if __name__ == "__main__":
    main()
