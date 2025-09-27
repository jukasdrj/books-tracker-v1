#!/bin/bash
# 🚀 Enhanced Cloudflare Workers Monitoring & Debugging Commands
# Comprehensive logging infrastructure for performance optimization and cache analysis

set -e

# === COLORS FOR OUTPUT ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Enhanced Cloudflare Workers Monitoring System${NC}"
echo -e "${CYAN}=========================================${NC}"

# === WORKER CONFIGURATION ===
WORKERS=(
    "books-api-proxy"
    "personal-library-cache-warmer"
    "openlibrary-search-worker-production"
    "isbndb-biography-worker-production"
)

# === ANALYTICS DATASETS ===
DATASETS=(
    "books_api_performance"
    "books_api_cache_metrics"
    "books_api_provider_performance"
    "cache_warmer_performance"
    "openlibrary_performance"
    "isbndb_worker_performance"
)

# === REAL-TIME MONITORING FUNCTIONS ===

monitor_all_workers() {
    echo -e "${GREEN}📊 Starting real-time monitoring for all workers${NC}"

    # Create monitoring session
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_dir="logs/monitoring_session_${timestamp}"
    mkdir -p "$log_dir"

    # Start tail sessions for each worker
    for worker in "${WORKERS[@]}"; do
        echo -e "${YELLOW}🔍 Starting tail for ${worker}${NC}"

        # Performance monitoring
        wrangler tail "$worker" \
            --format json \
            --status error,ok \
            --output "${log_dir}/${worker}_performance.log" &

        # Cache-specific monitoring
        wrangler tail "$worker" \
            --format pretty \
            --search "CACHE\|HIT\|MISS" \
            --output "${log_dir}/${worker}_cache.log" &

        # Error monitoring
        wrangler tail "$worker" \
            --format pretty \
            --status error \
            --output "${log_dir}/${worker}_errors.log" &
    done

    echo -e "${GREEN}✅ All monitoring sessions started. Logs in: ${log_dir}${NC}"
    echo -e "${CYAN}Press Ctrl+C to stop monitoring${NC}"

    # Keep monitoring alive
    wait
}

# === STEPHEN KING CACHE INVESTIGATION ===

investigate_stephen_king_cache() {
    echo -e "${PURPLE}🔍 STEPHEN KING CACHE INVESTIGATION${NC}"
    echo -e "${CYAN}=====================================${NC}"

    # Test queries that should find Stephen King
    local queries=(
        "stephen king"
        "Stephen King"
        "STEPHEN KING"
        "king stephen"
        "The Shining"
        "It stephen king"
        "Doctor Sleep"
    )

    for query in "${queries[@]}"; do
        echo -e "${YELLOW}🔍 Testing query: '${query}'${NC}"

        # Test main API
        echo "📡 Testing books-api-proxy..."
        response=$(curl -s "https://books-api-proxy.jukasdrj.workers.dev/search?q=${query// /%20}&maxResults=5" | jq -r '.results | length // 0')
        echo -e "   Results: ${response}"

        # Test with cache bypass
        echo "🚫 Testing with cache bypass..."
        response_bypass=$(curl -s "https://books-api-proxy.jukasdrj.workers.dev/search?q=${query// /%20}&maxResults=5&force=true" | jq -r '.results | length // 0')
        echo -e "   Results (bypass): ${response_bypass}"

        # Check cache directly
        echo "📦 Checking KV cache..."
        cache_key="search_$(echo "${query}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g')"
        cache_result=$(wrangler kv key get --binding CACHE --remote "${cache_key}" 2>/dev/null || echo "NOT_FOUND")

        if [ "$cache_result" != "NOT_FOUND" ]; then
            echo -e "   ${GREEN}✅ Found in cache${NC}"
        else
            echo -e "   ${RED}❌ Not in cache${NC}"
        fi

        echo "---"
    done

    # Investigate author cache specifically
    echo -e "${PURPLE}👤 AUTHOR CACHE INVESTIGATION${NC}"

    local author_keys=(
        "author_biography_stephen_king"
        "author_stephen_king"
        "stephen_king"
        "author_king_stephen"
    )

    for key in "${author_keys[@]}"; do
        echo -e "${YELLOW}🔍 Checking author key: '${key}'${NC}"
        result=$(wrangler kv key get --binding CACHE --remote "${key}" 2>/dev/null || echo "NOT_FOUND")

        if [ "$result" != "NOT_FOUND" ]; then
            echo -e "   ${GREEN}✅ Found in KV${NC}"
            # Show first 200 chars of result
            echo "   Preview: $(echo "$result" | head -c 200)..."
        else
            echo -e "   ${RED}❌ Not found in KV${NC}"
        fi
    done

    # Check R2 storage
    echo -e "${PURPLE}💾 R2 STORAGE INVESTIGATION${NC}"

    echo "📦 Checking R2 bucket contents..."
    wrangler r2 object list personal-library-data --prefix "author" --limit 10

    # Check for Stephen King specifically
    local r2_keys=(
        "author_stephen_king.json"
        "stephen_king.json"
        "authors/stephen_king.json"
    )

    for key in "${r2_keys[@]}"; do
        echo -e "${YELLOW}🔍 Checking R2 key: '${key}'${NC}"
        result=$(wrangler r2 object get personal-library-data "${key}" 2>/dev/null || echo "NOT_FOUND")

        if [ "$result" != "NOT_FOUND" ]; then
            echo -e "   ${GREEN}✅ Found in R2${NC}"
        else
            echo -e "   ${RED}❌ Not found in R2${NC}"
        fi
    done
}

# === CACHE WARMING ANALYSIS ===

analyze_cache_warming() {
    echo -e "${PURPLE}🔥 CACHE WARMING ANALYSIS${NC}"
    echo -e "${CYAN}=========================${NC}"

    # Count cached authors
    echo "📊 Counting cached authors..."
    cached_count=$(wrangler kv key list --binding CACHE --remote | grep -c "author_biography_" || echo "0")
    echo -e "   Cached authors: ${GREEN}${cached_count}${NC}"

    # Get recent cache entries
    echo "📋 Recent cache entries..."
    wrangler kv key list --binding CACHE --remote | grep "author_biography_" | head -10

    # Check cache warming status
    echo "🔥 Cache warming status..."
    curl -s "https://personal-library-cache-warmer.jukasdrj.workers.dev/stats"

    # Test cache warming
    echo -e "${YELLOW}🧪 Testing cache warming for Stephen King specifically...${NC}"
    curl -X POST "https://personal-library-cache-warmer.jukasdrj.workers.dev/warm" \
        -H "Content-Type: application/json" \
        -d '{
            "strategy": "targeted",
            "authors": ["Stephen King"],
            "force": true
        }'

    echo "⏳ Waiting 30 seconds for processing..."
    sleep 30

    # Check if Stephen King was cached
    echo "🔍 Checking if Stephen King is now cached..."
    stephen_king_result=$(wrangler kv key get --binding CACHE --remote "author_biography_stephen_king" 2>/dev/null || echo "NOT_FOUND")

    if [ "$stephen_king_result" != "NOT_FOUND" ]; then
        echo -e "   ${GREEN}✅ Stephen King successfully cached!${NC}"
    else
        echo -e "   ${RED}❌ Stephen King still not cached${NC}"
        echo -e "   ${YELLOW}ℹ️  This indicates a deeper issue with the caching system${NC}"
    fi
}

# === PERFORMANCE ANALYTICS ===

get_performance_analytics() {
    echo -e "${PURPLE}📈 PERFORMANCE ANALYTICS${NC}"
    echo -e "${CYAN}========================${NC}"

    local start_date=$(date -d '1 day ago' +%Y-%m-%d)
    local end_date=$(date +%Y-%m-%d)

    echo "📊 Querying performance data from ${start_date} to ${end_date}..."

    for dataset in "${DATASETS[@]}"; do
        echo -e "${YELLOW}📋 Dataset: ${dataset}${NC}"

        # Query analytics data
        wrangler analytics query \
            --dataset "$dataset" \
            --start-date "$start_date" \
            --end-date "$end_date" \
            --dimensions timestamp \
            --metrics count,sum \
            --limit 100 || echo "   No data available"

        echo "---"
    done
}

# === PROVIDER HEALTH CHECK ===

check_provider_health() {
    echo -e "${PURPLE}🌐 PROVIDER HEALTH CHECK${NC}"
    echo -e "${CYAN}========================${NC}"

    # Test each provider directly
    local providers=(
        "https://books-api-proxy.jukasdrj.workers.dev/health"
        "https://isbndb-biography-worker-production.jukasdrj.workers.dev/health"
        "https://personal-library-cache-warmer.jukasdrj.workers.dev/health"
    )

    for provider in "${providers[@]}"; do
        echo -e "${YELLOW}🔍 Testing: ${provider}${NC}"

        start_time=$(date +%s%3N)
        response=$(curl -s -o /dev/null -w "%{http_code}" "$provider" || echo "FAILED")
        end_time=$(date +%s%3N)
        duration=$((end_time - start_time))

        if [ "$response" = "200" ]; then
            echo -e "   ${GREEN}✅ Healthy (${duration}ms)${NC}"
        else
            echo -e "   ${RED}❌ Failed (${response})${NC}"
        fi
    done

    # Test actual search functionality
    echo -e "${YELLOW}🔍 Testing search functionality...${NC}"

    test_queries=("Andy Weir" "Martha Wells" "Stephen King")

    for query in "${test_queries[@]}"; do
        echo -e "   Testing: ${query}"

        start_time=$(date +%s%3N)
        result=$(curl -s "https://books-api-proxy.jukasdrj.workers.dev/search?q=${query// /%20}&maxResults=1" | jq -r '.results | length // 0')
        end_time=$(date +%s%3N)
        duration=$((end_time - start_time))

        if [ "$result" -gt 0 ]; then
            echo -e "     ${GREEN}✅ ${result} results (${duration}ms)${NC}"
        else
            echo -e "     ${RED}❌ No results (${duration}ms)${NC}"
        fi
    done
}

# === CACHE DEBUGGING ===

debug_cache_layers() {
    echo -e "${PURPLE}🐛 CACHE LAYER DEBUGGING${NC}"
    echo -e "${CYAN}=========================${NC}"

    local test_key="debug_test_$(date +%s)"
    local test_value='{"test": "value", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'

    echo "🧪 Testing KV cache operations..."

    # Test write
    echo "✍️  Writing test value..."
    wrangler kv key put --binding CACHE --remote "$test_key" "$test_value"

    # Test read
    echo "📖 Reading test value..."
    result=$(wrangler kv key get --binding CACHE --remote "$test_key")

    if [ "$result" = "$test_value" ]; then
        echo -e "   ${GREEN}✅ KV read/write working${NC}"
    else
        echo -e "   ${RED}❌ KV read/write failed${NC}"
        echo "   Expected: $test_value"
        echo "   Got: $result"
    fi

    # Clean up
    echo "🧹 Cleaning up test key..."
    wrangler kv key delete --binding CACHE --remote "$test_key"

    # Test R2 operations
    echo "🧪 Testing R2 operations..."

    echo "$test_value" | wrangler r2 object put personal-library-data "test/$test_key.json"
    r2_result=$(wrangler r2 object get personal-library-data "test/$test_key.json")

    if [ "$r2_result" = "$test_value" ]; then
        echo -e "   ${GREEN}✅ R2 read/write working${NC}"
    else
        echo -e "   ${RED}❌ R2 read/write failed${NC}"
    fi

    # Clean up
    wrangler r2 object delete personal-library-data "test/$test_key.json"
}

# === COMPREHENSIVE SYSTEM CHECK ===

comprehensive_system_check() {
    echo -e "${BLUE}🔍 COMPREHENSIVE SYSTEM CHECK${NC}"
    echo -e "${CYAN}==============================${NC}"

    check_provider_health
    echo ""
    debug_cache_layers
    echo ""
    analyze_cache_warming
    echo ""
    investigate_stephen_king_cache
    echo ""
    get_performance_analytics

    echo -e "${GREEN}🎉 System check complete!${NC}"
}

# === QUICK STEPHEN KING FIX ===

quick_stephen_king_fix() {
    echo -e "${PURPLE}⚡ QUICK STEPHEN KING CACHE FIX${NC}"
    echo -e "${CYAN}===============================${NC}"

    echo "🔥 Forcing Stephen King cache warming..."

    # Multiple approaches to cache Stephen King
    local stephen_king_queries=(
        '{"strategy": "targeted", "authors": ["Stephen King"], "force": true}'
        '{"strategy": "targeted", "authors": ["stephen king"], "force": true}'
        '{"strategy": "targeted", "authors": ["STEPHEN KING"], "force": true}'
        '{"strategy": "targeted", "authors": ["King, Stephen"], "force": true}'
    )

    for query in "${stephen_king_queries[@]}"; do
        echo "📡 Trying: $query"
        curl -X POST "https://personal-library-cache-warmer.jukasdrj.workers.dev/warm" \
            -H "Content-Type: application/json" \
            -d "$query"
        sleep 5
    done

    echo "⏳ Waiting for processing..."
    sleep 30

    # Verify caching worked
    echo "🔍 Verifying Stephen King is cached..."

    local verification_keys=(
        "author_biography_stephen_king"
        "author_biography_stephen_king"
        "stephen_king"
        "search_stephen_king"
    )

    local success=false

    for key in "${verification_keys[@]}"; do
        result=$(wrangler kv key get --binding CACHE --remote "$key" 2>/dev/null || echo "NOT_FOUND")
        if [ "$result" != "NOT_FOUND" ]; then
            echo -e "   ${GREEN}✅ Found Stephen King in cache (key: ${key})${NC}"
            success=true
            break
        fi
    done

    if [ "$success" = false ]; then
        echo -e "   ${RED}❌ Stephen King still not cached${NC}"
        echo "   🔧 Manual intervention required"

        # Try direct API test
        echo "🧪 Testing direct API..."
        curl -s "https://books-api-proxy.jukasdrj.workers.dev/search?q=stephen%20king&maxResults=1&force=true" | jq '.'
    else
        echo -e "${GREEN}🎉 Stephen King cache fix successful!${NC}"
    fi
}

# === MAIN MENU ===

show_menu() {
    echo ""
    echo -e "${BLUE}📋 MONITORING MENU${NC}"
    echo "1. 🔍 Comprehensive System Check"
    echo "2. 👤 Stephen King Cache Investigation"
    echo "3. ⚡ Quick Stephen King Fix"
    echo "4. 🔥 Cache Warming Analysis"
    echo "5. 🌐 Provider Health Check"
    echo "6. 🐛 Cache Layer Debugging"
    echo "7. 📊 Real-time Worker Monitoring"
    echo "8. 📈 Performance Analytics"
    echo "9. 🚪 Exit"
    echo ""
    read -p "Select option (1-9): " choice

    case $choice in
        1) comprehensive_system_check ;;
        2) investigate_stephen_king_cache ;;
        3) quick_stephen_king_fix ;;
        4) analyze_cache_warming ;;
        5) check_provider_health ;;
        6) debug_cache_layers ;;
        7) monitor_all_workers ;;
        8) get_performance_analytics ;;
        9) echo -e "${GREEN}👋 Goodbye!${NC}"; exit 0 ;;
        *) echo -e "${RED}❌ Invalid option${NC}"; show_menu ;;
    esac
}

# === SCRIPT EXECUTION ===

# Check if specific function requested
if [ $# -gt 0 ]; then
    case $1 in
        "stephen-king") quick_stephen_king_fix ;;
        "health") check_provider_health ;;
        "cache") debug_cache_layers ;;
        "monitor") monitor_all_workers ;;
        "analytics") get_performance_analytics ;;
        "check") comprehensive_system_check ;;
        *) echo -e "${RED}❌ Unknown command: $1${NC}"; show_menu ;;
    esac
else
    show_menu
fi